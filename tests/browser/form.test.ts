import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import {
  createDriver,
  findNode,
  leaksSecret,
  makeExecution,
  refOf,
  type DriverFixture,
} from './helpers.js'

describe('form type / click / select', () => {
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

  it('types, clicks a checkbox, selects an option, and redacts the password', async () => {
    const sessionId = `form-${++sessionSeq}`
    const execution = makeExecution(sessionId, fixture.workspaceRoot)

    const opened = await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/') },
      execution,
    )
    const s0 = opened.snapshot

    const usernameRef = refOf(s0, 'textbox', 'Username')
    const s1 = (
      await fixture.driver.action(
        { surface: 'browser', action: 'type', ref: usernameRef, text: 'alice', snapshotId: s0.id },
        execution,
      )
    ).snapshot

    const agreeRef = refOf(s1, 'checkbox', 'I agree')
    const s2 = (
      await fixture.driver.action(
        { surface: 'browser', action: 'click', ref: agreeRef, snapshotId: s1.id },
        execution,
      )
    ).snapshot

    const choiceRef = refOf(s2, 'combobox', 'Choice')
    const s3 = (
      await fixture.driver.action(
        { surface: 'browser', action: 'select', ref: choiceRef, option: 'two', snapshotId: s2.id },
        execution,
      )
    ).snapshot

    const passwordRef = refOf(s3, 'textbox', 'Password')
    await fixture.driver.action(
      { surface: 'browser', action: 'type', ref: passwordRef, text: 's3cret-value', snapshotId: s3.id },
      execution,
    )

    const final = await fixture.driver.observe({ surface: 'browser' }, execution)

    const username = findNode(final, (n) => n.role === 'textbox' && n.name === 'Username')
    expect(username?.value).toBe('alice')

    const agree = findNode(final, (n) => n.role === 'checkbox' && n.name === 'I agree')
    expect(agree?.states).toContain('checked')

    const choice = findNode(final, (n) => n.role === 'combobox' && n.name === 'Choice')
    expect(choice?.value).toBe('Two')

    // The password secret must never appear in any node name/value.
    expect(leaksSecret(final, 's3cret-value')).toBe(false)
    const password = findNode(final, (n) => n.role === 'textbox' && n.name === 'Password')
    expect(password).toBeDefined()
    expect(password?.value).toBeUndefined()
  })
})
