import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, makeExecution, type DriverFixture } from './helpers.js'

describe('tabs', () => {
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

  it('creates, switches, and closes tabs', async () => {
    const execution = makeExecution('tabs-1', fixture.workspaceRoot)

    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      execution,
    )

    const withSecond = await fixture.driver.action(
      { surface: 'browser', action: 'new_tab', url: server.url('/nav-b') },
      execution,
    )
    expect(withSecond.snapshot.metadata.tabs?.length).toBe(2)
    expect(withSecond.snapshot.metadata.url).toBe(server.url('/nav-b'))
    const activeTab = withSecond.snapshot.metadata.tabs?.find((t) => t.active)
    expect(activeTab?.url).toBe(server.url('/nav-b'))

    const firstTab = withSecond.snapshot.metadata.tabs?.find((t) => t.url === server.url('/'))
    expect(firstTab?.id).toBeTruthy()

    const switched = await fixture.driver.action(
      { surface: 'browser', action: 'switch_tab', tabId: firstTab!.id },
      execution,
    )
    expect(switched.snapshot.metadata.url).toBe(server.url('/'))

    const closed = await fixture.driver.action(
      { surface: 'browser', action: 'close_tab', tabId: firstTab!.id },
      execution,
    )
    expect(closed.snapshot.metadata.tabs?.length).toBe(1)
    expect(closed.snapshot.metadata.url).toBe(server.url('/nav-b'))
  })

  it('rejects switching to an unknown tab', async () => {
    const execution = makeExecution('tabs-2', fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      execution,
    )
    await expect(
      fixture.driver.action({ surface: 'browser', action: 'switch_tab', tabId: 'tab-999' }, execution),
    ).rejects.toMatchObject({ code: 'NOT_FOUND' })
  })
})
