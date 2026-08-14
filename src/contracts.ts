export type ComputerSurface = 'browser' | 'desktop'
export type ObservationDetail = 'interactive' | 'full' | 'changes'
export type OcrMode = 'auto' | 'always' | 'never'

export interface Rect {
  x: number
  y: number
  width: number
  height: number
}

export interface SemanticNode {
  ref?: string
  depth: number
  role: string
  name?: string
  value?: string
  description?: string
  states?: string[]
  actions?: string[]
  frame?: Rect
  source: 'accessibility' | 'ocr'
  interactive: boolean
}

export interface PermissionState {
  accessibility: boolean
  screenCapture: boolean
  aquaSession: boolean
  screenLocked: boolean
}

export interface SurfaceMetadata {
  title?: string
  url?: string
  appName?: string
  bundleId?: string
  pid?: number
  windowTitle?: string
  windowId?: number
  windowFrame?: Rect
  tabId?: string
  tabs?: Array<{ id: string; title: string; url: string; active: boolean }>
  viewport?: Rect
  displays?: Rect[]
  focusedRef?: string
}

export interface ComputerSnapshot {
  id: string
  surface: ComputerSurface
  createdAt: number
  metadata: SurfaceMetadata
  permissions?: PermissionState
  nodes: SemanticNode[]
  warnings: string[]
  truncated: boolean
  screenshotPath?: string
}

export interface ObserveRequest {
  surface: ComputerSurface
  detail?: ObservationDetail
  query?: string
  ocr?: OcrMode
  saveScreenshot?: boolean
}

export type ComputerActionName =
  | 'open_url'
  | 'back'
  | 'forward'
  | 'reload'
  | 'new_tab'
  | 'switch_tab'
  | 'close_tab'
  | 'launch_app'
  | 'focus'
  | 'click'
  | 'double_click'
  | 'hover'
  | 'type'
  | 'press'
  | 'select'
  | 'scroll'
  | 'drag'
  | 'upload_files'
  | 'wait'

export interface ActionRequest {
  surface: ComputerSurface
  action: ComputerActionName
  snapshotId?: string
  ref?: string
  toRef?: string
  text?: string
  key?: string
  url?: string
  tabId?: string
  app?: string
  option?: string
  direction?: 'up' | 'down' | 'left' | 'right'
  amount?: number
  x?: number
  y?: number
  toX?: number
  toY?: number
  replace?: boolean
  paths?: string[]
  durationMs?: number
}

export interface ComputerExecution {
  sessionId: string
  workspaceRoot: string
  signal: AbortSignal
}

export interface ObservationResult {
  surface: ComputerSurface
  snapshotId: string
  text: string
  truncated: boolean
  warnings: string[]
  screenshotPath?: string
}

export interface ActionResult extends ObservationResult {
  action: ComputerActionName
  status: string
}

export interface NativeTargetDescriptor {
  bundleId?: string
  pid?: number
  windowId?: number
  windowFrame?: Rect
  path?: number[]
  role?: string
  name?: string
  identifier?: string
  frame?: Rect
  ocrText?: string
}

export interface NativeNode {
  role: string
  name?: string
  value?: string
  description?: string
  enabled?: boolean
  focused?: boolean
  selected?: boolean
  actions?: string[]
  frame?: Rect
  depth: number
  secure?: boolean
  target?: NativeTargetDescriptor
  source?: 'ax' | 'accessibility' | 'ocr'
}

export interface NativeObservation {
  permissions: PermissionState
  appName?: string
  bundleId?: string
  pid?: number
  windowTitle?: string
  windowId?: number
  windowFrame?: Rect
  displays?: Rect[]
  nodes: NativeNode[]
  warnings?: string[]
  screenshotPath?: string
}

export interface NativeStatus {
  protocolVersion: number
  helperVersion: string
  permissions: PermissionState
  socketPath?: string
}

export interface NativeRpcRequest {
  id: string
  method: string
  params?: Record<string, unknown>
}

export interface NativeRpcResponse {
  id: string
  ok: boolean
  result?: unknown
  error?: { code: string; message: string }
}

export const COMPUTER_PROTOCOL_VERSION = 1
export const DEFAULT_MAX_OBSERVATION_CHARS = 20_000
export const DEFAULT_MAX_NODES = 250
