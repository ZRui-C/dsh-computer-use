import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { startFixtureServer, type FixtureServer } from './fixtures.js'
import { createDriver, findNode, makeExecution, refOf, type DriverFixture } from './helpers.js'

describe('scroll and upload', () => {
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

  it('scrolls the page by a direction and amount', async () => {
    const execution = makeExecution('scroll-1', fixture.workspaceRoot)
    await fixture.driver.action(
      { surface: 'browser', action: 'open_url', url: server.url('/scroll.html') },
      execution,
    )
    const before = await fixture.driver.observe({ surface: 'browser' }, execution)
    const top = findNode(before, (n) => n.name === 'TOP MARKER')
    expect(top?.frame).toBeDefined()

    const scrolled = await fixture.driver.action(
      { surface: 'browser', action: 'scroll', direction: 'down', amount: 500 },
      execution,
    )
    const after = scrolled.snapshot
    const topAfter = findNode(after, (n) => n.name === 'TOP MARKER')

    expect(topAfter?.frame?.y).toBeLessThan((top!.frame!.y as number) - 400)
  })

  it('accepts an upload inside the workspace and fences everything else', async () => {
    const execution = makeExecution('upload-1', fixture.workspaceRoot)
    const inside = path.join(fixture.workspaceRoot, 'upload.txt')
    await fs.promises.writeFile(inside, 'hello from workspace')

    const outsideDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'outside-ws-'))
    const outside = path.join(outsideDir, 'outside.txt')
    await fs.promises.writeFile(outside, 'secret')

    try {
      const opened = await fixture.driver.action(
        { surface: 'browser', action: 'open_url', url: server.url('/upload.html') },
        execution,
      )
      const inputRef = refOf(opened.snapshot, 'button', 'file upload')

      const ok = await fixture.driver.action(
        { surface: 'browser', action: 'upload_files', ref: inputRef, paths: [inside], snapshotId: opened.snapshot.id },
        execution,
      )
      expect(ok.status).toBe('success')

      await expect(
        fixture.driver.action(
          { surface: 'browser', action: 'upload_files', ref: inputRef, paths: [outside], snapshotId: ok.snapshot.id },
          execution,
        ),
      ).rejects.toMatchObject({ code: 'UPLOAD_OUT_OF_WORKSPACE' })
    } finally {
      await fs.promises.rm(outsideDir, { recursive: true, force: true })
    }
  })
})
