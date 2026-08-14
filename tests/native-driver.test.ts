import os from 'node:os'
import { describe, expect, it, vi } from 'vitest'
import { resolveConfig } from '../src/config.js'
import type { NativeObservation } from '../src/contracts.js'
import { NativeClient } from '../src/native/client.js'
import { NativeDesktopDriver } from '../src/native/driver.js'

function observation(accessibility = true): NativeObservation {
  return {
    permissions: {
      accessibility,
      screenCapture: true,
      aquaSession: true,
      screenLocked: false,
    },
    appName: 'Fixture',
    bundleId: 'test.fixture',
    pid: 42,
    windowTitle: 'Fixture window',
    displays: [{ x: 0, y: 0, width: 1440, height: 900 }],
    nodes: [
      {
        role: 'AXButton',
        name: 'Native button',
        depth: 1,
        source: 'accessibility',
        actions: ['AXPress'],
        frame: { x: 10, y: 20, width: 100, height: 30 },
        target: { pid: 42, role: 'AXButton', name: 'Native button', path: [0], frame: { x: 10, y: 20, width: 100, height: 30 } },
      },
      {
        role: 'AXStaticText',
        name: 'Painted control',
        depth: 0,
        source: 'ocr',
        frame: { x: 200, y: 100, width: 80, height: 20 },
      },
    ],
    warnings: [],
  }
}

function fixture(accessibility = true): {
  driver: NativeDesktopDriver
  calls: Array<Record<string, unknown>>
} {
  const calls: Array<Record<string, unknown>> = []
  const fake = {
    observeDesktop: vi.fn(async () => observation(accessibility)),
    performDesktop: vi.fn(async (params: Record<string, unknown>) => {
      calls.push(params)
      return { status: 'ok' }
    }),
    status: vi.fn(async () => ({
      protocolVersion: 1,
      helperVersion: 'test',
      permissions: observation(accessibility).permissions,
    })),
    ocrFile: vi.fn(async () => []),
    dispose: vi.fn(async () => undefined),
  } as unknown as NativeClient
  return {
    driver: new NativeDesktopDriver(fake, resolveConfig({ stateDir: os.tmpdir(), actionSettleMs: 0 })),
    calls,
  }
}

const execution = {
  sessionId: 'native-test',
  workspaceRoot: os.tmpdir(),
  signal: new AbortController().signal,
}

describe('NativeDesktopDriver protocol adapter', () => {
  it('normalizes AX roles and gives OCR-only text a coordinate ref', async () => {
    const { driver } = fixture()
    const snapshot = await driver.observe({ surface: 'desktop', ocr: 'always' }, execution)
    expect(snapshot.nodes.find((node) => node.name === 'Native button')).toMatchObject({ role: 'button', ref: 'd1', interactive: true })
    expect(snapshot.nodes.find((node) => node.name === 'Painted control')).toMatchObject({ role: 'text', ref: 'o1', interactive: true, source: 'ocr' })
  })

  it('encodes an OCR ref click as the Swift discriminated action shape', async () => {
    const { driver, calls } = fixture()
    const snapshot = await driver.observe({ surface: 'desktop' }, execution)
    await driver.action({ surface: 'desktop', action: 'click', ref: 'o1', snapshotId: snapshot.id }, execution)
    expect(calls[0]).toEqual({
      type: 'click',
      point: { x: 240, y: 110 },
      button: 'left',
      count: 1,
      target: {
        bundleId: 'test.fixture',
        pid: 42,
        frame: { x: 200, y: 100, width: 80, height: 20 },
        ocrText: 'Painted control',
      },
    })
  })

  it('routes key input to the last observed process without requiring a ref', async () => {
    const { driver, calls } = fixture()
    await driver.observe({ surface: 'desktop' }, execution)
    await driver.action({ surface: 'desktop', action: 'press', key: 'ENTER' }, execution)
    expect(calls[0]).toEqual({
      type: 'press',
      keys: ['ENTER'],
      target: {
        bundleId: 'test.fixture',
        pid: 42,
        role: 'AXWindow',
        name: 'Fixture window',
      },
    })
  })

  it('fails closed on a stale snapshot and missing Accessibility permission', async () => {
    const first = fixture()
    const snapshot = await first.driver.observe({ surface: 'desktop' }, execution)
    await expect(first.driver.action({ surface: 'desktop', action: 'click', ref: 'd1', snapshotId: 'old' }, execution)).rejects.toMatchObject({ code: 'STALE_SNAPSHOT' })

    const denied = fixture(false)
    const deniedSnapshot = await denied.driver.observe({ surface: 'desktop' }, execution)
    await expect(denied.driver.action({ surface: 'desktop', action: 'click', ref: 'd1', snapshotId: deniedSnapshot.id }, execution)).rejects.toMatchObject({ code: 'PERMISSION_REQUIRED' })
    const deniedWithoutSnapshot = fixture(false)
    await expect(deniedWithoutSnapshot.driver.action({ surface: 'desktop', action: 'press', key: 'ENTER' }, execution)).rejects.toMatchObject({ code: 'PERMISSION_REQUIRED' })
    expect(snapshot.permissions?.accessibility).toBe(true)
  })
})
