import path from 'node:path'
import type { ActionRequest, ComputerActionName } from './contracts.js'
import { ComputerUseError } from './errors.js'

const browserActions = new Set<ComputerActionName>([
  'open_url', 'back', 'forward', 'reload', 'new_tab', 'switch_tab', 'close_tab',
  'click', 'double_click', 'hover', 'type', 'press', 'select', 'scroll', 'drag',
  'upload_files', 'wait',
])

const desktopActions = new Set<ComputerActionName>([
  'launch_app', 'focus', 'click', 'double_click', 'hover', 'type', 'press',
  'scroll', 'drag', 'wait',
])

const snapshotActions = new Set<ComputerActionName>([
  'click', 'double_click', 'hover', 'type', 'select', 'scroll', 'drag', 'upload_files',
])

function invalid(message: string): never {
  throw new ComputerUseError('INVALID_ACTION', message)
}

function hasPoint(request: ActionRequest): boolean {
  return request.x !== undefined && request.y !== undefined
}

function hasDestination(request: ActionRequest): boolean {
  return request.toRef !== undefined || (request.toX !== undefined && request.toY !== undefined)
}

export function validateActionRequest(request: ActionRequest): void {
  const supported = request.surface === 'browser' ? browserActions : desktopActions
  if (!supported.has(request.action)) {
    invalid(`${request.action} is not supported on ${request.surface}`)
  }
  if (snapshotActions.has(request.action) && request.snapshotId === undefined) {
    invalid(`${request.action} requires snapshot_id from the latest computer_observe result`)
  }

  switch (request.action) {
    case 'open_url':
      if (request.url === undefined || request.url.trim().length === 0) invalid('open_url requires url')
      try {
        const url = new URL(request.url)
        if (!['http:', 'https:', 'about:'].includes(url.protocol)) invalid(`unsupported URL protocol: ${url.protocol}`)
      } catch (error) {
        if (error instanceof ComputerUseError) throw error
        invalid(`invalid URL: ${request.url}`)
      }
      return
    case 'switch_tab':
      if (request.tabId === undefined) invalid('switch_tab requires tab_id')
      return
    case 'launch_app':
      if (request.app === undefined || request.app.trim().length === 0) invalid('launch_app requires app')
      return
    case 'focus':
      if (request.ref === undefined && (request.app === undefined || request.app.trim().length === 0)) {
        invalid('focus requires ref or app')
      }
      return
    case 'click':
    case 'double_click':
    case 'hover':
      if (request.ref === undefined && !hasPoint(request)) invalid(`${request.action} requires ref or x and y`)
      return
    case 'type':
      if (request.text === undefined) invalid('type requires text')
      if (request.ref === undefined && !hasPoint(request)) invalid('type requires ref or x and y')
      return
    case 'press':
      if (request.key === undefined || request.key.trim().length === 0) invalid('press requires key')
      return
    case 'select':
      if (request.ref === undefined || request.option === undefined) invalid('select requires ref and option')
      return
    case 'scroll':
      if (request.direction === undefined) invalid('scroll requires direction')
      if (request.amount !== undefined && (!Number.isFinite(request.amount) || request.amount <= 0)) {
        invalid('scroll amount must be a positive number')
      }
      return
    case 'drag':
      if (request.ref === undefined && !hasPoint(request)) invalid('drag requires a source ref or x and y')
      if (!hasDestination(request)) invalid('drag requires to_ref or to_x and to_y')
      return
    case 'upload_files':
      if (request.ref === undefined) invalid('upload_files requires a file-input ref')
      if (request.paths === undefined || request.paths.length === 0) invalid('upload_files requires paths')
      return
    case 'wait': {
      const duration = request.durationMs ?? 500
      if (!Number.isFinite(duration) || duration < 0 || duration > 10_000) {
        invalid('wait duration_ms must be between 0 and 10000')
      }
      return
    }
    case 'back':
    case 'forward':
    case 'reload':
    case 'new_tab':
    case 'close_tab':
      return
  }
}

export function resolveWorkspacePaths(paths: string[], workspaceRoot: string): string[] {
  const root = path.resolve(workspaceRoot)
  return paths.map((input) => {
    const resolved = path.resolve(root, input)
    const relative = path.relative(root, resolved)
    if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      throw new ComputerUseError('UPLOAD_OUT_OF_WORKSPACE', `upload path is outside the session workspace: ${input}`)
    }
    return resolved
  })
}
