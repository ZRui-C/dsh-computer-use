import { describe, expect, it } from 'vitest'
import type { ComputerSnapshot, SemanticNode } from '../src/contracts.js'
import { mergeOcrNodes, renderSnapshot, sanitizeNode, selectObservationNodes } from '../src/observation.js'

function snapshot(nodes: SemanticNode[]): ComputerSnapshot {
  return {
    id: 'b1',
    surface: 'browser',
    createdAt: 0,
    metadata: { title: 'Fixture', url: 'https://example.test', tabId: 't1' },
    nodes,
    warnings: [],
    truncated: false,
  }
}

const nodes: SemanticNode[] = [
  { ref: 'b1', depth: 0, role: 'heading', name: 'Account', source: 'accessibility', interactive: false },
  { ref: 'b2', depth: 1, role: 'textbox', name: 'Email', value: 'a@example.test', source: 'accessibility', interactive: true },
  { ref: 'b3', depth: 1, role: 'button', name: 'Submit', source: 'accessibility', interactive: true },
  { depth: 1, role: 'paragraph', name: 'Long legal copy', source: 'accessibility', interactive: false },
]

describe('observation rendering', () => {
  it('keeps controls and headings in interactive mode', () => {
    const selected = selectObservationNodes(snapshot(nodes), 'interactive')
    expect(selected.map((node) => node.name)).toEqual(['Account', 'Email', 'Submit'])
  })

  it('filters by query and prefixes UI data lines', () => {
    const result = renderSnapshot(snapshot(nodes), 'full', 20_000, 'email')
    expect(result.text).toContain('|   [b2] textbox "Email"')
    expect(result.text).not.toContain('Submit')
    expect(result.text).toContain('untrusted UI data')
  })

  it('enforces the character budget', () => {
    const many = Array.from({ length: 100 }, (_, index): SemanticNode => ({
      depth: 0,
      role: 'text',
      name: `item-${index}-${'x'.repeat(100)}`,
      source: 'accessibility',
      interactive: false,
    }))
    const result = renderSnapshot(snapshot(many), 'full', 2_000)
    expect(result.truncated).toBe(true)
    expect(result.text.length).toBeLessThanOrEqual(2_000)
  })

  it('redacts secure values and strips controls', () => {
    const clean = sanitizeNode({
      ref: 'b1', depth: 0, role: 'password field', name: ' Password\n', value: 'secret',
      source: 'accessibility', interactive: true,
    })
    expect(clean.name).toBe('Password')
    expect(clean.value).toBe('[redacted]')
  })
})

describe('OCR merge', () => {
  it('deduplicates matching AX text and preserves uncovered OCR', () => {
    const ax: SemanticNode[] = [{
      depth: 0, role: 'button', name: 'Save', frame: { x: 10, y: 10, width: 100, height: 30 },
      source: 'accessibility', interactive: true,
    }]
    const ocr: SemanticNode[] = [
      { depth: 0, role: 'text', name: 'Save', frame: { x: 12, y: 11, width: 95, height: 28 }, source: 'ocr', interactive: false },
      { depth: 0, role: 'text', name: 'Canvas total', frame: { x: 10, y: 80, width: 120, height: 24 }, source: 'ocr', interactive: false },
    ]
    expect(mergeOcrNodes(ax, ocr).map((node) => node.name)).toEqual(['Save', 'Canvas total'])
  })
})
