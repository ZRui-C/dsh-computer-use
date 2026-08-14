import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, findNode, makeExecution, type DriverFixture } from './helpers.js'

describe('iframes and shadow DOM', () => {
  let server: FixtureServer
  let fixture: DriverFixture

  beforeAll(async () => {
    server = await startFixtureServer()
    fixture = await createDriver()
  })

  afterAll(async () => {
    await fixture.dispose()
    await server.close()
  })

  it('includes iframe content in the semantic snapshot', async () => {
    const execution = makeExecution('frames-1', fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/frames.html') },
      execution,
    )
    const snapshot = await fixture.driver.observe({ surface: 'browser' }, execution)

    const frameHeading = findNode(snapshot, (n) => n.name === 'Inside frame')
    expect(frameHeading).toBeDefined()
    expect(frameHeading?.role).toBe('heading')

    const frameButton = findNode(snapshot, (n) => n.role === 'button' && n.name === 'Frame button')
    expect(frameButton).toBeDefined()
  })

  it('includes shadow DOM content in the semantic snapshot', async () => {
    const execution = makeExecution('frames-2', fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/frames.html') },
      execution,
    )
    const snapshot = await fixture.driver.observe({ surface: 'browser' }, execution)

    const shadowButton = findNode(snapshot, (n) => n.role === 'button' && n.name === 'Shadow button')
    expect(shadowButton).toBeDefined()
  })
})
