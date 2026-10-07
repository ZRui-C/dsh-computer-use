import { describe, expect, it, vi } from 'vitest'
import type { SubprocessRuntime } from '@deepseek-ai/dsh-subprocess'
import { NativeClient } from '../src/native/client.js'

function fixture() {
  const client = new NativeClient({} as SubprocessRuntime, { socketPath: '/unused', stateDir: '/unused' })
  // Stub only the transport, leaving request construction and wire normalization real.
  const request = vi.spyOn(client as unknown as {
    request: (method: string, params: Record<string, unknown>, signal?: AbortSignal) => Promise<unknown>
  }, 'request')
  return { client, request }
}

const signal = new AbortController().signal

describe('native wire compatibility', () => {
  it('sends ordered OCR languages to the helper', async () => {
    const { client, request } = fixture()
    request.mockResolvedValue({ observations: [] })
    await client.ocrFile('/fixture.png', signal, ['zh-Hans', 'en-US'])
    expect(request).toHaveBeenCalledWith('ocrFile', {
      path: '/fixture.png', languages: ['zh-Hans', 'en-US'],
    }, signal)
  })

  it.each([undefined, false, true])('normalizes optional native truncation: %s', async (truncated) => {
    const { client, request } = fixture()
    request.mockResolvedValue({
      permissions: { accessibility: true, screenCapture: false, aquaSession: true, screenLocked: false },
      displays: [], nodes: [], warnings: [],
      ...(truncated === undefined ? {} : { truncated }),
    })
    expect((await client.observeDesktop({}, signal)).truncated).toBe(truncated ?? false)
  })
})
