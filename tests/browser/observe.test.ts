import fs from 'node:fs'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, findNode, makeExecution, refOf, type DriverFixture } from './helpers.js'
import type { ObserveRequest } from '../../src/contracts.js'

describe('observe', () => {
  let server: FixtureServer
  let fixture: DriverFixture
  let sessionSeq = 0

  beforeAll(async () => {
    server = await startFixtureServer()
    fixture = await createDriver()
  })

  afterAll(async () => {
    await fixture.dispose()
    await server.close()
  })

  const nextSession = () => `obs-${++sessionSeq}`

  it('returns a text-only semantic snapshot with no inline image bytes', async () => {
    const sessionId = nextSession()
    const execution = makeExecution(sessionId, fixture.workspaceRoot)

    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      execution,
    )

    const request: ObserveRequest = { surface: 'browser', saveScreenshot: true }
    const snapshot = await fixture.driver.observe(request, execution)

    expect(snapshot.surface).toBe('browser')
    expect(snapshot.nodes.length).toBeGreaterThan(0)
    expect(snapshot.id).toBeTruthy()

    // Text-only: names and values must be strings, never byte payloads.
    for (const node of snapshot.nodes) {
      expect(node.source).toBe('accessibility')
      if (node.name !== undefined) expect(typeof node.name).toBe('string')
      if (node.value !== undefined) expect(typeof node.value).toBe('string')
      expect(node.frame?.width ?? 0).toBeGreaterThanOrEqual(0)
    }

    // Screenshot is saved to disk as a path, never inlined into the snapshot.
    expect(snapshot.screenshotPath).toBeTruthy()
    const serialized = JSON.stringify(snapshot)
    expect(serialized).not.toContain('data:image/png;base64')

    const png = await fs.promises.readFile(snapshot.screenshotPath!)
    expect(png.subarray(0, 8)).toEqual(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  })

  it('keeps refs stable across snapshots and mints fresh snapshot ids', async () => {
    const sessionId = nextSession()
    const execution = makeExecution(sessionId, fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      execution,
    )

    const first = await fixture.driver.observe({ surface: 'browser' }, execution)
    const second = await fixture.driver.observe({ surface: 'browser' }, execution)

    expect(first.id).not.toBe(second.id)
    expect(refOf(first, 'button', 'Submit')).toBe(refOf(second, 'button', 'Submit'))

    const heading = findNode(first, (n) => n.role === 'heading')
    expect(heading).toBeDefined()
    expect(heading?.name).toBe('Form page')
  })

  it('records page metadata including tabs and viewport', async () => {
    const sessionId = nextSession()
    const execution = makeExecution(sessionId, fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      execution,
    )
    const snapshot = await fixture.driver.observe({ surface: 'browser' }, execution)

    expect(snapshot.metadata.url).toBe(server.url('/'))
    expect(snapshot.metadata.title).toBe('Form')
    expect(snapshot.metadata.tabs?.length).toBe(1)
    expect(snapshot.metadata.tabs?.[0]?.active).toBe(true)
    expect(snapshot.metadata.viewport?.width).toBeGreaterThan(0)
    expect(snapshot.metadata.viewport?.height).toBeGreaterThan(0)
  })
})
