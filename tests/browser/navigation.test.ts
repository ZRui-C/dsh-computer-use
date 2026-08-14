import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, makeExecution, refOf, type DriverFixture } from './helpers.js'

describe('navigation staleness', () => {
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

  it('rejects a ref action against an outdated snapshot id after navigation', async () => {
    const sessionId = `nav-${++sessionSeq}`
    const execution = makeExecution(sessionId, fixture.workspaceRoot)

    const opened = await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/nav-a') },
      execution,
    )
    const buttonRef = refOf(opened.snapshot, 'button', 'Button A')

    // Navigate away, producing a newer snapshot.
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/nav-b') },
      execution,
    )

    await expect(
      fixture.driver.action(
        { surface: 'browser', action: 'click', ref: buttonRef, snapshotId: opened.snapshot.id },
        execution,
      ),
    ).rejects.toMatchObject({ code: 'STALE_SNAPSHOT' })
  })

  it('rejects a ref that belongs to a document that navigated away', async () => {
    const sessionId = `nav-${++sessionSeq}`
    const execution = makeExecution(sessionId, fixture.workspaceRoot)

    const opened = await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/nav-a') },
      execution,
    )
    const buttonRef = refOf(opened.snapshot, 'button', 'Button A')

    // Click the link: this navigates to /nav-b and returns a fresh snapshot,
    // whose id is now the "current" one. The old ref no longer exists.
    const linkRef = refOf(opened.snapshot, 'link', 'Go to B')
    const navigated = await fixture.driver.action(
      { surface: 'browser', action: 'click', ref: linkRef, snapshotId: opened.snapshot.id },
      execution,
    )
    expect(navigated.snapshot.metadata.url).toBe(server.url('/nav-b'))

    await expect(
      fixture.driver.action(
        { surface: 'browser', action: 'click', ref: buttonRef, snapshotId: navigated.snapshot.id },
        execution,
      ),
    ).rejects.toMatchObject({ code: 'STALE_REF' })
  })

  it('supports back and forward navigation', async () => {
    const sessionId = `nav-${++sessionSeq}`
    const execution = makeExecution(sessionId, fixture.workspaceRoot)

    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/nav-a') },
      execution,
    )
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/nav-b') },
      execution,
    )
    const back = await fixture.driver.action({ surface: 'browser', action: 'back' }, execution)
    expect(back.snapshot.metadata.url).toBe(server.url('/nav-a'))

    const forward = await fixture.driver.action({ surface: 'browser', action: 'forward' }, execution)
    expect(forward.snapshot.metadata.url).toBe(server.url('/nav-b'))
  })
})
