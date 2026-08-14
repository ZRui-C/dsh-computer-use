import type { Context } from '@deepseek-ai/cordis'
import type { Agent } from '@deepseek-ai/dsh-agent'
import type {
  ActionRequest,
  ActionResult,
  ComputerExecution,
  ComputerSnapshot,
  NativeStatus,
  ObserveRequest,
  ObservationResult,
} from './contracts.js'
import { validateActionRequest } from './actions.js'
import { BrowserDriver } from './browser/index.js'
import { Config, resolveConfig, type ComputerUseConfig, type ResolvedComputerUseConfig } from './config.js'
import { NativeClient, NativeDesktopDriver } from './native/index.js'
import { renderSnapshot } from './observation.js'
import { ComputerUseService } from './service.js'

export const name = 'computer-use-host'
export const inject = ['subprocess']
export { Config }

export default class ComputerUseRuntime extends ComputerUseService {
  static Config = Config
  static inject = ['subprocess']

  private readonly config: ResolvedComputerUseConfig
  private readonly browser: BrowserDriver
  private readonly native: NativeDesktopDriver
  private readonly nativeClient: NativeClient
  private readonly previous = new Map<string, ComputerSnapshot>()
  private disposed = false

  constructor(ctx: Context, config: ComputerUseConfig = {}) {
    super(ctx)
    this.config = resolveConfig(config)
    this.nativeClient = new NativeClient(ctx.subprocess, {
      socketPath: this.config.helperSocketPath,
      stateDir: this.config.stateDir,
      ...(this.config.helperAppPath === undefined ? {} : { appPath: this.config.helperAppPath }),
    })
    this.native = new NativeDesktopDriver(this.nativeClient, this.config)
    this.browser = new BrowserDriver(this.config, {
      ocr: async (png, execution) => await this.native.ocrBuffer(png, execution),
    })

    ctx.on('agent/disposed', ({ agent }: { agent: Agent }) => this.cleanupSession(agent.id))
    ctx.effect(() => () => this.disposeRuntime(), 'computer-use host teardown')
  }

  async observe(request: ObserveRequest, execution: ComputerExecution): Promise<ObservationResult> {
    this.assertLive()
    const key = snapshotKey(execution.sessionId, request.surface)
    const previous = this.previous.get(key)
    const snapshot = request.surface === 'browser'
      ? await this.browser.observe(request, execution)
      : await this.native.observe(request, execution)
    this.previous.set(key, snapshot)
    return renderSnapshot(
      snapshot,
      request.detail ?? 'interactive',
      this.config.maxObservationChars,
      request.query,
      previous,
    )
  }

  async action(request: ActionRequest, execution: ComputerExecution): Promise<ActionResult> {
    this.assertLive()
    validateActionRequest(request)
    const key = snapshotKey(execution.sessionId, request.surface)
    const previous = this.previous.get(key)
    const result = request.surface === 'browser'
      ? await this.browser.action(request, execution)
      : await this.native.action(request, execution)
    this.previous.set(key, result.snapshot)
    const observation = renderSnapshot(
      result.snapshot,
      'changes',
      this.config.maxObservationChars,
      undefined,
      previous,
    )
    return {
      ...observation,
      action: request.action,
      status: result.status,
    }
  }

  async nativeStatus(signal?: AbortSignal): Promise<NativeStatus> {
    this.assertLive()
    return await this.nativeClient.status(signal)
  }

  private async cleanupSession(sessionId: string): Promise<void> {
    this.native.clearSession(sessionId)
    this.previous.delete(snapshotKey(sessionId, 'browser'))
    this.previous.delete(snapshotKey(sessionId, 'desktop'))
    await this.browser.cleanupSession(sessionId)
  }

  private async disposeRuntime(): Promise<void> {
    if (this.disposed) return
    this.disposed = true
    this.previous.clear()
    await Promise.allSettled([this.browser.dispose(), this.native.dispose()])
  }

  private assertLive(): void {
    if (this.disposed) throw new Error('computer-use host service is disposed')
  }
}

function snapshotKey(sessionId: string, surface: 'browser' | 'desktop'): string {
  return `${sessionId}:${surface}`
}
