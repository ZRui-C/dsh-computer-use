import type { Rect } from '../contracts.js'

/**
 * Minimal structural mirrors of the Chrome DevTools Protocol shapes consumed by
 * the browser driver. We deliberately avoid importing playwright-core's
 * internal `Protocol` namespace (it is not re-exported), so these types only
 * describe the fields we actually read. The real CDP responses are cast to
 * them at the call site.
 */

export interface AxValue {
  type?: string
  value?: unknown
  relatedNodes?: AxRelatedNode[]
}

export interface AxRelatedNode {
  backendDOMNodeId?: number
  idref?: string
  text?: string
}

export interface AxProperty {
  name?: string
  value?: AxValue
}

export interface AxNode {
  nodeId?: string
  ignored?: boolean
  ignoredReasons?: AxProperty[]
  role?: AxValue
  chromeRole?: AxValue
  name?: AxValue
  description?: AxValue
  value?: AxValue
  properties?: AxProperty[]
  parentId?: string
  childIds?: string[]
  backendDOMNodeId?: number
  frameId?: string
}

export interface FrameTreeNode {
  frame: { id: string; url: string; name?: string }
  childFrames?: FrameTreeNode[]
}

export interface RareStringData {
  index: number[]
  value: number[]
}

export interface RareBooleanData {
  index: number[]
}

export interface NodeTreeSnapshot {
  nodeName?: number[]
  backendNodeId?: number[]
  attributes?: number[][]
  isClickable?: RareBooleanData
}

export interface LayoutTreeSnapshot {
  nodeIndex: number[]
  bounds: number[][]
}

export interface DocumentSnapshot {
  frameId: number
  nodes: NodeTreeSnapshot
  layout: LayoutTreeSnapshot
  scrollOffsetX?: number
  scrollOffsetY?: number
}

export interface CaptureSnapshotResult {
  documents: DocumentSnapshot[]
  strings: string[]
}

export interface FrameSnapData {
  frameId: string
  scrollX: number
  scrollY: number
  /** backendNodeId -> document-space bounds (scroll offset NOT applied). */
  bounds: Map<number, Rect>
  /** backendNodeIds that belong to `<input type="password">`. */
  passwordNodes: Set<number>
  /** backendNodeIds that respond to mouse clicks (DOMSnapshot isClickable). */
  clickableNodes: Set<number>
}

function stringsAt(indices: number[] | undefined, strings: string[]): string[] {
  if (!indices) return []
  return indices.map((i) => strings[i] ?? '')
}

/**
 * Decode the compact `DOMSnapshot.captureSnapshot` output into per-frame
 * geometry and security metadata. Frames are keyed by their CDP frame id.
 */
export function decodeDocumentSnapshots(
  result: CaptureSnapshotResult,
): Map<string, FrameSnapData> {
  const { documents, strings } = result
  const out = new Map<string, FrameSnapData>()

  for (const doc of documents) {
    const frameId = strings[doc.frameId] ?? `doc-${out.size}`
    const nodes = doc.nodes
    const layout = doc.layout

    const backendNodeIds = nodes.backendNodeId ?? []
    const bounds = new Map<number, Rect>()
    for (let li = 0; li < layout.nodeIndex.length; li++) {
      const domIndex = layout.nodeIndex[li]
      if (domIndex === undefined) continue
      const b = layout.bounds[li]
      if (!b || b.length < 4) continue
      const backend = backendNodeIds[domIndex]
      if (backend === undefined) continue
      if (!bounds.has(backend)) {
        bounds.set(backend, {
          x: b[0] ?? 0,
          y: b[1] ?? 0,
          width: b[2] ?? 0,
          height: b[3] ?? 0,
        })
      }
    }

    const nodeNames = stringsAt(nodes.nodeName, strings)
    const attributes = nodes.attributes ?? []
    const passwordNodes = new Set<number>()
    for (let di = 0; di < nodeNames.length; di++) {
      if (nodeNames[di]?.toUpperCase() !== 'INPUT') continue
      const attrs = stringsAt(attributes[di], strings)
      let type = ''
      for (let a = 0; a + 1 < attrs.length; a += 2) {
        if (attrs[a] === 'type') {
          type = attrs[a + 1] ?? ''
          break
        }
      }
      if (type.toLowerCase() === 'password') {
        const backend = backendNodeIds[di]
        if (backend !== undefined) passwordNodes.add(backend)
      }
    }

    const clickableNodes = new Set<number>()
    for (const index of nodes.isClickable?.index ?? []) {
      const backend = backendNodeIds[index]
      if (backend !== undefined) clickableNodes.add(backend)
    }

    out.set(frameId, {
      frameId,
      scrollX: doc.scrollOffsetX ?? 0,
      scrollY: doc.scrollOffsetY ?? 0,
      bounds,
      passwordNodes,
      clickableNodes,
    })
  }

  return out
}

/** Extract the primitive value of an AX property, if it is a string/number. */
export function axValueString(value: AxValue | undefined): string | undefined {
  if (!value) return undefined
  const v = value.value
  if (typeof v === 'string') return v.length > 0 ? v : undefined
  if (typeof v === 'number') return String(v)
  return undefined
}
