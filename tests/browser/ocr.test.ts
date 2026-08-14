import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, makeExecution, type DriverFixture } from './helpers.js'

describe('text-only OCR fallback', () => {
  let server: FixtureServer
  let fixture: DriverFixture
  let callbackSignal: AbortSignal | undefined

  beforeAll(async () => {
    server = await startFixtureServer()
    fixture = await createDriver({
      ocr: async (_png, context) => {
        callbackSignal = context.signal
        return [{ text: 'Visual Submit', confidence: 0.97, frame: { x: 20, y: 20, width: 120, height: 40 } }]
      },
    })
  })

  afterAll(async () => {
    await fixture.dispose()
    await server.close()
  })

  it('turns OCR text into a clickable ref and returns post-action text', async () => {
    const execution = makeExecution('ocr-click', fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/ocr-only.html') },
      execution,
    )
    const snapshot = await fixture.driver.observe(
      { surface: 'browser', ocr: 'always' },
      execution,
    )
    const ocrNode = snapshot.nodes.find((node) => node.source === 'ocr' && node.name === 'Visual Submit')
    expect(callbackSignal).toBe(execution.signal)
    expect(ocrNode?.ref).toMatch(/^b\d+$/)
    expect(ocrNode?.interactive).toBe(true)
    if (ocrNode?.ref === undefined) throw new Error('OCR node did not receive a ref')

    const result = await fixture.driver.action(
      {
        surface: 'browser',
        action: 'click',
        ref: ocrNode!.ref,
        snapshotId: snapshot.id,
      },
      execution,
    )
    expect(result.snapshot.nodes.some((node) => node.name === 'visual control clicked')).toBe(true)
  })
})
