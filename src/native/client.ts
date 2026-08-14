import { existsSync } from 'node:fs'
import fs from 'node:fs/promises'
import net from 'node:net'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { SubprocessRuntime } from '@deepseek-ai/dsh-subprocess'
import type {
  NativeNode,
  NativeObservation,
  NativeRpcRequest,
  NativeRpcResponse,
  NativeStatus,
  PermissionState,
  Rect,
} from '../contracts.js'
import { COMPUTER_PROTOCOL_VERSION } from '../contracts.js'
import { abortError, ComputerUseError, throwIfAborted } from '../errors.js'
import { ensurePrivateDirectory } from '../fs-utils.js'
import { abortableSleep } from '../sleep.js'

interface PendingRequest {
  resolve: (value: unknown) => void
  reject: (error: Error) => void
  signal?: AbortSignal
  onAbort?: () => void
  aborted: boolean
}

interface WireHandshake {
  protocolVersion: number
  helperVersion: string
}

interface WireStatus {
  permissions: PermissionState
  socketPath?: string
}

interface WireTarget {
  bundleId?: string
  pid?: number
  windowId?: number
  windowFrame?: Rect
  role?: string
  name?: string
  identifier?: string
  path?: number[]
  frame?: Rect
  ocrText?: string
}

interface WireNode extends Omit<NativeNode, 'target'> {
  target?: WireTarget
}

interface WireObservation {
  frontmostApp?: { bundleId?: string; name?: string; pid: number }
  frontmostWindow?: { title?: string; frame?: Rect; windowId?: number }
  displays: Array<{ frame: Rect; isMain: boolean }>
  permissions: PermissionState
  warnings: string[]
  screenshotPath?: string
  nodes: WireNode[]
}

interface WireActionResult {
  performed: boolean
  action: string
  method?: string
  detail?: string
}

interface WireOcrResult {
  observations: Array<{ text: string; confidence: number; frame: Rect }>
}

export interface NativeClientOptions {
  appPath?: string
  socketPath: string
  stateDir: string
}

export class NativeClient {
  private socket: net.Socket | undefined
  private buffer = ''
  private counter = 0
  private readonly pending = new Map<string, PendingRequest>()
  private connecting: Promise<void> | undefined
  private handshake: WireHandshake | undefined
  private disposed = false

  constructor(
    private readonly subprocess: SubprocessRuntime,
    private readonly options: NativeClientOptions,
  ) {}

  async status(signal?: AbortSignal): Promise<NativeStatus> {
    const result = await this.request<WireStatus>('status', {}, signal)
    const handshake = this.requireHandshake()
    return {
      protocolVersion: handshake.protocolVersion,
      helperVersion: handshake.helperVersion,
      permissions: result.permissions,
      ...(result.socketPath === undefined ? {} : { socketPath: result.socketPath }),
    }
  }

  async observeDesktop(params: Record<string, unknown>, signal: AbortSignal): Promise<NativeObservation> {
    const result = await this.request<WireObservation>('observeDesktop', params, signal)
    const app = result.frontmostApp
    return {
      permissions: result.permissions,
      ...(app?.name === undefined ? {} : { appName: app.name }),
      ...(app?.bundleId === undefined ? {} : { bundleId: app.bundleId }),
      ...(app?.pid === undefined ? {} : { pid: app.pid }),
      ...(result.frontmostWindow?.title === undefined ? {} : { windowTitle: result.frontmostWindow.title }),
      ...(result.frontmostWindow?.windowId === undefined ? {} : { windowId: result.frontmostWindow.windowId }),
      ...(result.frontmostWindow?.frame === undefined ? {} : { windowFrame: result.frontmostWindow.frame }),
      displays: result.displays.map((display) => display.frame),
      nodes: result.nodes.map((node) => ({
        ...node,
        source: node.source === 'ocr' ? 'ocr' : 'accessibility',
        ...(node.target === undefined
          ? {}
          : {
              target: {
                ...node.target,
                ...(app?.bundleId === undefined ? {} : { bundleId: app.bundleId }),
              },
            }),
      })),
      warnings: [...result.warnings],
      ...(result.screenshotPath === undefined ? {} : { screenshotPath: result.screenshotPath }),
    }
  }

  async performDesktop(params: Record<string, unknown>, signal: AbortSignal): Promise<{ status: string }> {
    const result = await this.request<WireActionResult>('performDesktop', params, signal)
    if (!result.performed) throw new ComputerUseError('NATIVE_ACTION_FAILED', `${result.action} was not performed`)
    const status = [result.method, result.detail].filter((value): value is string => value !== undefined && value.length > 0).join(': ')
    return { status: status.length === 0 ? 'ok' : status }
  }

  async ocrFile(filePath: string, signal: AbortSignal): Promise<Array<{ text: string; confidence: number; frame: Rect }>> {
    const result = await this.request<WireOcrResult>('ocrFile', { path: filePath }, signal)
    return result.observations
  }

  async dispose(): Promise<void> {
    if (this.disposed) return
    if (this.socket !== undefined && !this.socket.destroyed) {
      await this.request('shutdown', {}).catch(() => undefined)
    }
    this.disposed = true
    const socket = this.socket
    this.socket = undefined
    socket?.destroy()
    this.rejectAll(new ComputerUseError('NATIVE_DISPOSED', 'native computer-use client was disposed'))
  }

  private async request<T>(method: string, params: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
    if (this.disposed) throw new ComputerUseError('NATIVE_DISPOSED', 'native computer-use client was disposed')
    if (signal !== undefined) throwIfAborted(signal)
    await this.ensureConnected(signal)
    const socket = this.socket
    if (socket === undefined || socket.destroyed) throw new ComputerUseError('NATIVE_DISCONNECTED', 'native helper is not connected')

    const id = `n${++this.counter}`
    const request: NativeRpcRequest = { id, method, params }
    return await new Promise<T>((resolve, reject) => {
      const pending: PendingRequest = {
        resolve: (value) => resolve(value as T),
        reject,
        aborted: false,
        ...(signal === undefined ? {} : { signal }),
      }
      if (signal !== undefined) {
        pending.onAbort = () => {
          pending.aborted = true
          this.sendCancelOutOfBand(id)
        }
        signal.addEventListener('abort', pending.onAbort, { once: true })
      }
      this.pending.set(id, pending)
      try {
        this.write(request)
      } catch (error) {
        this.pending.delete(id)
        this.clearPending(pending)
        reject(error instanceof Error ? error : new Error(String(error)))
      }
    })
  }

  private async ensureConnected(signal?: AbortSignal): Promise<void> {
    if (this.socket !== undefined && !this.socket.destroyed) return
    if (this.connecting !== undefined) return await this.connecting
    this.connecting = this.connect(signal)
    try {
      await this.connecting
    } finally {
      this.connecting = undefined
    }
  }

  private async connect(signal?: AbortSignal): Promise<void> {
    if (signal !== undefined) throwIfAborted(signal)
    await ensurePrivateDirectory(path.dirname(this.options.socketPath))
    let lastError: Error | undefined
    try {
      await this.openSocket(signal)
      await this.verifyHandshake(signal)
      return
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error))
    }

    await this.launchHelper(signal)
    for (let attempt = 0; attempt < 30; attempt += 1) {
      if (signal !== undefined) throwIfAborted(signal)
      try {
        await this.openSocket(signal)
        await this.verifyHandshake(signal)
        return
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error))
        this.socket?.destroy()
        this.socket = undefined
        await abortableSleep(100, signal ?? new AbortController().signal)
      }
    }
    throw new ComputerUseError('NATIVE_START_FAILED', `could not connect to native helper: ${lastError?.message ?? 'unknown error'}`)
  }

  private async launchHelper(signal?: AbortSignal): Promise<void> {
    const appPath = this.options.appPath ?? defaultAppPath()
    try {
      await fs.access(appPath)
    } catch {
      throw new ComputerUseError('NATIVE_HELPER_MISSING', `native helper app not found: ${appPath}; run pnpm build:native`)
    }
    const handle = this.subprocess.spawn({
      argv: ['/usr/bin/open', '-gjn', appPath, '--args', '--agent', '--socket', this.options.socketPath],
      cwd: path.dirname(appPath),
      stdio: {
        stdin: 'ignore',
        stdout: { maxBytes: 32_768 },
        stderr: { maxBytes: 32_768 },
      },
      graceMs: 1_000,
      ...(signal === undefined ? {} : { signal }),
    })
    const outcome = await handle.done
    if (outcome.exitCode !== 0) {
      const stderr = handle.collected.stderr?.readFrom(0).text.trim()
      throw new ComputerUseError('NATIVE_LAUNCH_FAILED', `LaunchServices failed to start helper${stderr === undefined || stderr.length === 0 ? '' : `: ${stderr}`}`)
    }
  }

  private async openSocket(signal?: AbortSignal): Promise<void> {
    if (signal !== undefined) throwIfAborted(signal)
    await new Promise<void>((resolve, reject) => {
      const socket = net.createConnection(this.options.socketPath)
      const cancel = () => socket.destroy(abortError())
      if (signal !== undefined) signal.addEventListener('abort', cancel, { once: true })
      socket.once('connect', () => {
        if (signal !== undefined) signal.removeEventListener('abort', cancel)
        this.attachSocket(socket)
        resolve()
      })
      socket.once('error', (error) => {
        if (signal !== undefined) signal.removeEventListener('abort', cancel)
        reject(error)
      })
    })
  }

  private attachSocket(socket: net.Socket): void {
    this.socket?.destroy()
    this.socket = socket
    this.buffer = ''
    socket.setEncoding('utf8')
    socket.on('data', (chunk: string) => this.onData(chunk))
    socket.on('error', (error) => this.rejectAll(new ComputerUseError('NATIVE_CONNECTION_ERROR', error.message, { cause: error })))
    socket.on('close', () => {
      if (this.socket === socket) this.socket = undefined
      this.rejectAll(new ComputerUseError('NATIVE_DISCONNECTED', 'native helper connection closed'))
    })
  }

  private async verifyHandshake(signal?: AbortSignal): Promise<void> {
    const result = await this.requestOnConnected<WireHandshake>('handshake', { protocolVersion: COMPUTER_PROTOCOL_VERSION }, signal)
    if (result.protocolVersion !== COMPUTER_PROTOCOL_VERSION) {
      throw new ComputerUseError('NATIVE_PROTOCOL_MISMATCH', `native helper protocol ${result.protocolVersion} does not match host ${COMPUTER_PROTOCOL_VERSION}`)
    }
    this.handshake = result
  }

  private requireHandshake(): WireHandshake {
    if (this.handshake === undefined) throw new ComputerUseError('NATIVE_PROTOCOL_ERROR', 'native helper handshake is missing')
    return this.handshake
  }

  private async requestOnConnected<T>(method: string, params: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
    const socket = this.socket
    if (socket === undefined || socket.destroyed) throw new ComputerUseError('NATIVE_DISCONNECTED', 'native helper is not connected')
    const id = `n${++this.counter}`
    return await new Promise<T>((resolve, reject) => {
      const pending: PendingRequest = {
        resolve: (value) => resolve(value as T),
        reject,
        aborted: false,
        ...(signal === undefined ? {} : { signal }),
      }
      this.pending.set(id, pending)
      this.write({ id, method, params })
    })
  }

  private write(request: NativeRpcRequest): void {
    const socket = this.socket
    if (socket === undefined || socket.destroyed) throw new ComputerUseError('NATIVE_DISCONNECTED', 'native helper is not connected')
    socket.write(`${JSON.stringify(request)}\n`)
  }

  private sendCancelOutOfBand(requestId: string): void {
    const socket = net.createConnection(this.options.socketPath)
    const timer = setTimeout(() => socket.destroy(), 1_000)
    socket.once('connect', () => {
      socket.end(`${JSON.stringify({ id: `cancel-${requestId}`, method: 'cancel', params: { requestId } })}\n`)
    })
    socket.once('close', () => clearTimeout(timer))
    socket.once('error', () => clearTimeout(timer))
  }

  private onData(chunk: string): void {
    this.buffer += chunk
    while (true) {
      const newline = this.buffer.indexOf('\n')
      if (newline < 0) return
      const line = this.buffer.slice(0, newline)
      this.buffer = this.buffer.slice(newline + 1)
      if (line.trim().length === 0) continue
      let response: NativeRpcResponse
      try {
        response = JSON.parse(line) as NativeRpcResponse
      } catch {
        this.socket?.destroy(new ComputerUseError('NATIVE_PROTOCOL_ERROR', 'native helper returned invalid JSON'))
        return
      }
      const pending = this.pending.get(response.id)
      if (pending === undefined) continue
      this.pending.delete(response.id)
      this.clearPending(pending)
      if (pending.aborted) pending.reject(abortError())
      else if (response.ok) pending.resolve(response.result)
      else pending.reject(new ComputerUseError(response.error?.code ?? 'NATIVE_ERROR', response.error?.message ?? 'native helper failed'))
    }
  }

  private clearPending(pending: PendingRequest): void {
    if (pending.signal !== undefined && pending.onAbort !== undefined) pending.signal.removeEventListener('abort', pending.onAbort)
  }

  private rejectAll(error: Error): void {
    for (const pending of this.pending.values()) {
      this.clearPending(pending)
      pending.reject(error)
    }
    this.pending.clear()
  }
}

function defaultAppPath(): string {
  const packageRoot = fileURLToPath(new URL('../../', import.meta.url))
  const embeddedApp = path.resolve(packageRoot, '../../..')
  const candidates = [
    process.env.DSH_COMPUTER_USE_APP_PATH,
    '/Applications/DSH Computer Use.app',
    path.basename(embeddedApp) === 'DSH Computer Use.app' ? embeddedApp : undefined,
    path.join(packageRoot, 'native', 'macos-helper', 'dist', 'DSH Computer Use.app'),
  ]
  return candidates.find((candidate): candidate is string => candidate !== undefined && existsSync(candidate))
    ?? '/Applications/DSH Computer Use.app'
}
