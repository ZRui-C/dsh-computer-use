import type { SemanticNode, Rect } from '../contracts.js'
import { axValueString, type AxNode } from './cdp.js'

const BOOLEAN_STATES = new Set([
  'busy',
  'disabled',
  'editable',
  'focusable',
  'focused',
  'hidden',
  'invalid',
  'modal',
  'multiline',
  'multiselectable',
  'readonly',
  'required',
  'selected',
  'expanded',
  'pressed',
  'checked',
  'settable',
  'atomic',
])

const MIXED_STATES = new Set(['checked', 'selected', 'pressed', 'expanded'])

const INTERACTIVE_ROLES = new Set([
  'button',
  'togglebutton',
  'link',
  'textbox',
  'searchbox',
  'combobox',
  'checkbox',
  'radio',
  'switch',
  'slider',
  'spinbutton',
  'tab',
  'menuitem',
  'menuitemcheckbox',
  'menuitemradio',
  'option',
  'listbox',
  'treeitem',
  'gridcell',
  'columnheader',
  'rowheader',
  'scrollbar',
  'progressbar',
  'textfield',
  'textarea',
  'select',
  'img',
  'iframe',
  'details',
  'summary',
  'document',
  'listitem',
])

/** Roles that are pure structural wrappers and add noise when empty. */
const SKIP_WHEN_EMPTY = new Set(['generic', 'genericcontainer', 'none', 'presentation'])

export interface BuildSemanticNodesOptions {
  /**
   * Viewport offset for this frame: main-frame viewport coordinates of the
   * frame's (0, 0) minus the frame's own scroll offset. Bounds from
   * DOMSnapshot are document-space, so `nodeFrame = offset + docBounds`.
   */
  viewportOffset?: { x: number; y: number }
  depthBase?: number
  bounds: Map<number, Rect>
  passwordNodes: Set<number>
  clickableNodes: Set<number>
  /**
   * Called for each node that has a backend node id so the driver can mint a
   * stable ref. Receives the final (main-frame viewport) bounds so the driver
   * can record them for later coordinate resolution.
   */
  assignRef?: (backendNodeId: number, frame: Rect | undefined) => string | undefined
}

function stateStrings(node: AxNode): string[] {
  const out: string[] = []
  for (const p of node.properties ?? []) {
    if (!p.name) continue
    const v = p.value?.value
    if (BOOLEAN_STATES.has(p.name)) {
      // Chromium reports tristate values ("checked", "selected", …) as the
      // strings "true"/"false"/"mixed", while booleans come through as `true`.
      if (v === true || v === 'true') out.push(p.name)
      else if (MIXED_STATES.has(p.name) && v === 'mixed') out.push(`${p.name}=mixed`)
    } else if (p.name === 'orientation' || p.name === 'level') {
      if (typeof v === 'string' || typeof v === 'number') out.push(`${p.name}=${v}`)
    }
  }
  return out
}

function actionStrings(node: AxNode): string[] {
  for (const p of node.properties ?? []) {
    if (p.name === 'actions' && Array.isArray(p.value?.value)) {
      return (p.value.value as unknown[]).map(String)
    }
  }
  return []
}

function isInteractive(
  role: string,
  states: string[],
  actions: string[],
  clickable: boolean,
): boolean {
  if (INTERACTIVE_ROLES.has(role)) return true
  if (states.includes('focusable') || states.includes('editable')) return true
  if (actions.length > 0) return true
  return clickable
}

function buildOne(
  node: AxNode,
  depth: number,
  offset: { x: number; y: number },
  opts: BuildSemanticNodesOptions,
): SemanticNode | undefined {
  const rawRole = axValueString(node.role) ?? axValueString(node.chromeRole)
  if (!rawRole) return undefined
  const role = rawRole.toLowerCase()

  const name = axValueString(node.name)
  const description = axValueString(node.description)
  const states = stateStrings(node)
  const actions = actionStrings(node)

  const backendNodeId = node.backendDOMNodeId
  const isPassword = backendNodeId !== undefined && opts.passwordNodes.has(backendNodeId)
  // Password values are never surfaced, regardless of what the AX tree exposes.
  const value = isPassword ? undefined : axValueString(node.value)
  const clickable = backendNodeId !== undefined && opts.clickableNodes.has(backendNodeId)

  const interactive = isInteractive(role, states, actions, clickable)

  // Skip structural wrappers that carry no information of their own.
  if (
    SKIP_WHEN_EMPTY.has(role) &&
    !interactive &&
    name === undefined &&
    value === undefined &&
    description === undefined
  ) {
    return undefined
  }

  let frame: Rect | undefined
  if (backendNodeId !== undefined) {
    const b = opts.bounds.get(backendNodeId)
    if (b !== undefined) {
      frame = { x: offset.x + b.x, y: offset.y + b.y, width: b.width, height: b.height }
    }
  }

  const result: SemanticNode = { depth, role, source: 'accessibility', interactive }
  if (backendNodeId !== undefined) {
    const ref = opts.assignRef?.(backendNodeId, frame)
    if (ref !== undefined) result.ref = ref
  }
  if (name !== undefined) result.name = name
  if (value !== undefined) result.value = value
  if (description !== undefined) result.description = description
  if (states.length > 0) result.states = states
  if (actions.length > 0) result.actions = actions
  if (frame !== undefined) result.frame = frame
  return result
}

/**
 * Flatten an AX tree into text-only semantic nodes. Ignored nodes are skipped
 * but their unignored descendants are promoted to the nearest visible
 * ancestor's level, so `depth` counts only meaningful levels.
 */
export function buildSemanticNodes(
  axNodes: AxNode[],
  opts: BuildSemanticNodesOptions,
): SemanticNode[] {
  const offset = opts.viewportOffset ?? { x: 0, y: 0 }
  const depthBase = opts.depthBase ?? 0

  const byId = new Map<string, AxNode>()
  for (const n of axNodes) {
    if (n.nodeId) byId.set(n.nodeId, n)
  }
  const roots = axNodes.filter((n) => n.parentId === undefined || !byId.has(n.parentId))

  const out: SemanticNode[] = []
  const visit = (node: AxNode, depth: number): void => {
    const ignored = node.ignored === true
    if (!ignored) {
      const built = buildOne(node, depth + depthBase, offset, opts)
      if (built) out.push(built)
    }
    for (const childId of node.childIds ?? []) {
      const child = byId.get(childId)
      if (child) visit(child, ignored ? depth : depth + 1)
    }
  }
  for (const root of roots) visit(root, 0)
  return out
}
