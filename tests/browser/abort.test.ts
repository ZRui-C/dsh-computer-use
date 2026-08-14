import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, makeExecution, type DriverFixture } from './helpers.js'

describe('abort signal', () => {
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

  it('closes the session context on abort and quiesces', async () => {
    const sessionId = 'abort-1'

    // Establish a context for the session with a live signal.
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      makeExecution(sessionId, fixture.workspaceRoot),
    )

    // Start a long wait, then abort it mid-flight.
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), 100)
    try {
      await expect(
        fixture.driver.action(
          { surface: 'browser', action: 'wait', durationMs: 30_000 },
          makeExecution(sessionId, fixture.workspaceRoot, controller.signal),
        ),
      ).rejects.toMatchObject({ code: 'ABORTED' })
    } finally {
      clearTimeout(timer)
    }

    // A fresh signal must still work: the driver recreates the closed context.
    const snapshot = await fixture.driver.observe(
      { surface: 'browser' },
      makeExecution(sessionId, fixture.workspaceRoot),
    )
    expect(snapshot.metadata.url).toBe('about:blank')
  })
})
