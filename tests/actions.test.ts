import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { resolveWorkspacePaths, validateActionRequest } from '../src/actions.js'

const snapshot = { surface: 'browser', snapshotId: 'b1' } as const

describe('validateActionRequest', () => {
  it('accepts a ref click with a current snapshot', () => {
    expect(() => validateActionRequest({ ...snapshot, action: 'click', ref: 'b2' })).not.toThrow()
  })

  it('rejects semantic actions without a snapshot', () => {
    expect(() => validateActionRequest({ surface: 'browser', action: 'type', ref: 'b2', text: 'hello' }))
      .toThrow(/snapshot_id/)
  })

  it('rejects surface-specific actions', () => {
    expect(() => validateActionRequest({ surface: 'desktop', action: 'open_url', url: 'https://example.com' }))
      .toThrow(/not supported/)
  })

  it('validates URLs and wait bounds', () => {
    expect(() => validateActionRequest({ surface: 'browser', action: 'open_url', url: 'file:///etc/passwd' }))
      .toThrow(/protocol/)
    expect(() => validateActionRequest({ surface: 'browser', action: 'wait', durationMs: 10_001 }))
      .toThrow(/10000/)
  })
})

describe('resolveWorkspacePaths', () => {
  it('normalizes in-workspace files', () => {
    expect(resolveWorkspacePaths(['fixtures/file.txt'], '/tmp/work')).toEqual([
      path.join('/tmp/work', 'fixtures/file.txt'),
    ])
  })

  it('rejects traversal outside the workspace', () => {
    expect(() => resolveWorkspacePaths(['../secret'], '/tmp/work')).toThrow(/outside/)
  })
})
