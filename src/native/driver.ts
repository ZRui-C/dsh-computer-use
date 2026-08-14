import fs from 'node:fs/promises'
import path from 'node:path'
import type {
  ActionRequest,
  ComputerExecution,
  ComputerSnapshot,
  NativeNode,
  NativeTargetDescriptor,
  ObserveRequest,
  Rect,
  SemanticNode,
} from '../contracts.js'
import type { ResolvedComputerUseConfig } from '../config.js'
import { ComputerUseError, throwIfAborted } from '../errors.js'
import { ensurePrivateDirectory } from '../fs-utils.js'
import { MonotonicIds } from '../ids.js'
import { AbortableMutex } from '../mutex.js'
import { abortableSleep } from '../sleep.js'
import { NativeClient } from './client.js'

interface NativeSnapshotState {
  snapshot: ComputerSnapshot
  targets: Map<string, NativeTargetDescriptor>
}

interface Point {
  x: number
  y: number
}

export class NativeDesktopDriver {
  private readonly ids = new MonotonicIds('d')
  private readonly inputMutex = new AbortableMutex()
  private readonly latest = new Map<string, NativeSnapshotState>()

  constructor(
    private readonly client: NativeClient,
    private readonly config: ResolvedComputerUseConfig,
  ) {}

  async observe(request: ObserveRequest, execution: ComputerExecution): Promise<ComputerSnapshot> {
    return await this.inputMutex.run(async () => await this.observeUnlocked(request, execution), execution.signal)
  }

  async action(request: ActionRequest, execution: ComputerExecution): Promise<{ status: string; snapshot: ComputerSnapshot }> {
    return await this.inputMutex.run(async () => {
      throwIfAborted(execution.signal)
      const previous = this.latest.get(execution.sessionId)
      const stickyTarget = keepsBackgroundTarget(request.action) ? snapshotTarget(previous) : undefined
      const status = await this.performAction(request, execution)
      await abortableSleep(this.config.actionSettleMs, execution.signal)
      const snapshot = await this.observeUnlocked(
        { surface: 'desktop', detail: 'changes', ocr: 'auto' },
        execution,
        stickyTarget,
      )
      return { status, snapshot }
    }, execution.signal)
  }

  async ocrBuffer(
    png: Buffer,
    execution: { sessionId: string; signal: AbortSignal },
  ): Promise<Array<{ text: string; frame: Rect; confidence: number }>> {
    const directory = path.join(this.config.stateDir, 'ocr', execution.sessionId)
    await ensurePrivateDirectory(directory)
    const filePath = path.join(directory, `${Date.now()}-${Math.random().toString(36).slice(2)}.png`)
    await fs.writeFile(filePath, png, { mode: 0o600 })
    try {
      return await this.client.ocrFile(filePath, execution.signal)
    } finally {
      await fs.unlink(filePath).catch(() => undefined)
    }
  }

  clearSession(sessionId: string): void {
    this.latest.delete(sessionId)
  }

  async dispose(): Promise<void> {
    this.latest.clear()
    await this.client.dispose()
  }

  private async observeUnlocked(
    request: ObserveRequest,
    execution: ComputerExecution,
    target?: NativeTargetDescriptor,
  ): Promise<ComputerSnapshot> {
    throwIfAborted(execution.signal)
    let screenshotPath: string | undefined
    if (request.saveScreenshot === true) {
      const directory = path.join(this.config.stateDir, 'screenshots', execution.sessionId)
      await ensurePrivateDirectory(directory)
      screenshotPath = path.join(directory, `${Date.now()}-desktop.png`)
    }
    const native = await this.client.observeDesktop({
      maxNodes: this.config.maxNodes,
      ocr: request.ocr ?? 'auto',
      ...(screenshotPath === undefined ? {} : { screenshotPath }),
      ...(target === undefined ? {} : { target }),
    }, execution.signal)
    const targets = new Map<string, NativeTargetDescriptor>()
    let axCounter = 0
    let ocrCounter = 0
    const nodes = native.nodes.slice(0, this.config.maxNodes).map((node) => {
      const isOcr = node.source === 'ocr'
      const target = node.target ?? (isOcr && node.frame !== undefined
        ? {
            ...(native.bundleId === undefined ? {} : { bundleId: native.bundleId }),
            ...(native.pid === undefined ? {} : { pid: native.pid }),
            ...(native.windowId === undefined ? {} : { windowId: native.windowId }),
            ...(native.windowFrame === undefined ? {} : { windowFrame: native.windowFrame }),
            frame: node.frame,
            ...(node.name === undefined ? {} : { ocrText: node.name }),
          }
        : undefined)
      const ref = target === undefined ? undefined : isOcr ? `o${++ocrCounter}` : `d${++axCounter}`
      if (ref !== undefined && target !== undefined) targets.set(ref, target)
      return nativeNode(node, ref)
    })
    const warnings = [...(native.warnings ?? [])]
    if (!native.permissions.accessibility) warnings.push('macOS Accessibility permission is required for desktop semantic control; grant it to DSH Computer Use.app in System Settings')
    if (!native.permissions.screenCapture && request.ocr !== 'never') warnings.push('Screen Recording permission is unavailable; OCR and desktop screenshots are disabled')
    const finalScreenshotPath = native.screenshotPath ?? screenshotPath
    const focused = nodes.find((node) => node.states?.includes('focused') === true)?.ref
    const snapshot: ComputerSnapshot = {
      id: this.ids.next(),
      surface: 'desktop',
      createdAt: Date.now(),
      metadata: {
        ...(native.appName === undefined ? {} : { appName: native.appName }),
        ...(native.bundleId === undefined ? {} : { bundleId: native.bundleId }),
        ...(native.pid === undefined ? {} : { pid: native.pid }),
        ...(native.windowTitle === undefined ? {} : { windowTitle: native.windowTitle }),
        ...(native.windowId === undefined ? {} : { windowId: native.windowId }),
        ...(native.windowFrame === undefined ? {} : { windowFrame: native.windowFrame }),
        ...(native.displays === undefined ? {} : { displays: native.displays }),
        ...(focused === undefined ? {} : { focusedRef: focused }),
      },
      permissions: native.permissions,
      nodes,
      warnings,
      truncated: native.nodes.length > this.config.maxNodes,
      ...(finalScreenshotPath === undefined ? {} : { screenshotPath: finalScreenshotPath }),
    }
    this.latest.set(execution.sessionId, { snapshot, targets })
    return snapshot
  }

  private async performAction(request: ActionRequest, execution: ComputerExecution): Promise<string> {
    const state = this.latest.get(execution.sessionId)
    const target = this.targetFor(request.ref, request, state)
    const toTarget = this.targetFor(request.toRef, request, state)
    const ambientTarget = snapshotTarget(state)
    const eventTarget = target ?? ambientTarget
    const needsAccessibility = request.action !== 'launch_app' && request.action !== 'wait'
    if (needsAccessibility) {
      const accessibility = state?.snapshot.permissions?.accessibility
        ?? (await this.client.status(execution.signal)).permissions.accessibility
      if (!accessibility) {
        throw new ComputerUseError('PERMISSION_REQUIRED', 'macOS Accessibility permission is required before desktop input can be sent')
      }
    }

    switch (request.action) {
      case 'launch_app':
        return (await this.client.performDesktop({ type: 'launchApp', appName: request.app }, execution.signal)).status
      case 'focus':
        if (target !== undefined) {
          return (await this.client.performDesktop({ type: 'focus', target, background: false }, execution.signal)).status
        }
        return (await this.client.performDesktop({ type: 'launchApp', appName: request.app }, execution.signal)).status
      case 'click':
        return (await this.client.performDesktop({
          type: 'click', point: pointFor(target, request.x, request.y), button: 'left', count: 1, target: eventTarget,
        }, execution.signal)).status
      case 'double_click':
        return (await this.client.performDesktop({
          type: 'doubleClick', point: pointFor(target, request.x, request.y), target: eventTarget,
        }, execution.signal)).status
      case 'hover':
        return (await this.client.performDesktop({
          type: 'hover', point: pointFor(target, request.x, request.y), target: eventTarget,
        }, execution.signal)).status
      case 'type':
        return await this.performType(request, target, eventTarget, execution)
      case 'press':
        return (await this.client.performDesktop({
          type: 'press', keys: [request.key], target: ambientTarget,
        }, execution.signal)).status
      case 'scroll': {
        const point = target === undefined && request.x === undefined
          ? centerOf(state?.snapshot.metadata.displays?.[0] ?? { x: 0, y: 0, width: 1, height: 1 })
          : pointFor(target, request.x, request.y)
        const amount = request.amount ?? 300
        const deltaX = request.direction === 'left' ? amount : request.direction === 'right' ? -amount : 0
        const deltaY = request.direction === 'up' ? amount : request.direction === 'down' ? -amount : 0
        return (await this.client.performDesktop({
          type: 'scroll', point, deltaX, deltaY, target: eventTarget,
        }, execution.signal)).status
      }
      case 'drag':
        return (await this.client.performDesktop({
          type: 'drag',
          from: pointFor(target, request.x, request.y),
          to: pointFor(toTarget, request.toX, request.toY),
          button: 'left',
          duration: (request.durationMs ?? 500) / 1_000,
          target: eventTarget,
        }, execution.signal)).status
      case 'wait':
        return (await this.client.performDesktop({ type: 'wait', milliseconds: request.durationMs ?? 500 }, execution.signal)).status
      default:
        throw new ComputerUseError('UNSUPPORTED_ACTION', `${request.action} is not a desktop action`)
    }
  }

  private async performType(
    request: ActionRequest,
    target: NativeTargetDescriptor | undefined,
    eventTarget: NativeTargetDescriptor | undefined,
    execution: ComputerExecution,
  ): Promise<string> {
    const text = request.text ?? ''
    if (target !== undefined && request.replace !== false) {
      try {
        return (await this.client.performDesktop({ type: 'setValue', value: text, target }, execution.signal)).status
      } catch (error) {
        if (execution.signal.aborted) throw error
      }
    }
    if (target !== undefined) {
      await this.client.performDesktop({ type: 'focus', target, background: true }, execution.signal)
    } else {
      await this.client.performDesktop({
        type: 'click',
        point: pointFor(undefined, request.x, request.y),
        button: 'left',
        count: 1,
        target: eventTarget,
      }, execution.signal)
    }
    if (request.replace !== false) {
      await this.client.performDesktop({ type: 'press', keys: ['META+A'], target: eventTarget }, execution.signal)
    }
    return (await this.client.performDesktop({ type: 'type', text, target: eventTarget }, execution.signal)).status
  }

  private targetFor(
    ref: string | undefined,
    request: ActionRequest,
    state: NativeSnapshotState | undefined,
  ): NativeTargetDescriptor | undefined {
    const needsSnapshot = ref !== undefined || request.toRef !== undefined || request.x !== undefined || request.y !== undefined
    if (needsSnapshot && (state === undefined || request.snapshotId !== state.snapshot.id)) {
      throw new ComputerUseError('STALE_SNAPSHOT', 'desktop snapshot is missing or stale; call computer_observe again')
    }
    if (ref === undefined) return undefined
    const target = state?.targets.get(ref)
    if (target === undefined) throw new ComputerUseError('STALE_REF', `desktop ref is no longer available: ${ref}`)
    return target
  }
}

function snapshotTarget(state: NativeSnapshotState | undefined): NativeTargetDescriptor | undefined {
  const metadata = state?.snapshot.metadata
  if (metadata?.pid === undefined) return undefined
  return {
    pid: metadata.pid,
    ...(metadata.bundleId === undefined ? {} : { bundleId: metadata.bundleId }),
    ...(metadata.windowId === undefined ? {} : { windowId: metadata.windowId }),
    ...(metadata.windowFrame === undefined ? {} : { windowFrame: metadata.windowFrame }),
    ...(metadata.windowTitle === undefined ? {} : { role: 'AXWindow', name: metadata.windowTitle }),
  }
}

function keepsBackgroundTarget(action: ActionRequest['action']): boolean {
  return ['click', 'double_click', 'hover', 'type', 'press', 'scroll', 'drag', 'wait'].includes(action)
}

function pointFor(target: NativeTargetDescriptor | undefined, x: number | undefined, y: number | undefined): Point {
  if (target?.frame !== undefined) return centerOf(target.frame)
  if (x === undefined || y === undefined) throw new ComputerUseError('INVALID_ACTION', 'desktop action requires a target ref or x and y')
  return { x, y }
}

function centerOf(frame: Rect): Point {
  return { x: frame.x + frame.width / 2, y: frame.y + frame.height / 2 }
}

function nativeNode(node: NativeNode, ref: string | undefined): SemanticNode {
  const states: string[] = []
  if (node.enabled === false) states.push('disabled')
  if (node.focused === true) states.push('focused')
  if (node.selected === true) states.push('selected')
  if (node.secure === true) states.push('secure')
  const role = normalizeAxRole(node.role)
  const interactive = ref !== undefined && (node.source === 'ocr' || (node.actions?.length ?? 0) > 0 || /button|field|box|menu|link|slider|tab|row|textbox/i.test(role))
  return {
    ...(ref === undefined ? {} : { ref }),
    depth: node.depth,
    role,
    ...(node.name === undefined ? {} : { name: node.name }),
    ...(node.secure === true ? { value: '[redacted]' } : node.value === undefined ? {} : { value: node.value }),
    ...(node.description === undefined ? {} : { description: node.description }),
    ...(states.length === 0 ? {} : { states }),
    ...(node.actions === undefined ? {} : { actions: node.actions }),
    ...(node.frame === undefined ? {} : { frame: node.frame }),
    source: node.source === 'ocr' ? 'ocr' : 'accessibility',
    interactive,
  }
}

function normalizeAxRole(role: string): string {
  const normalized = role.replace(/^AX/, '')
  const aliases: Record<string, string> = {
    Button: 'button', CheckBox: 'checkbox', ComboBox: 'combobox', Link: 'link',
    Menu: 'menu', MenuItem: 'menuitem', RadioButton: 'radio', SecureTextField: 'password textbox',
    StaticText: 'text', TextArea: 'textbox', TextField: 'textbox', Window: 'window',
  }
  return aliases[normalized] ?? normalized.toLocaleLowerCase()
}
