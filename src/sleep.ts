import { abortError, throwIfAborted } from './errors.js'

export async function abortableSleep(delayMs: number, signal: AbortSignal): Promise<void> {
  throwIfAborted(signal)
  if (delayMs <= 0) return
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(done, delayMs)
    function done(): void {
      signal.removeEventListener('abort', cancel)
      resolve()
    }
    function cancel(): void {
      clearTimeout(timer)
      reject(abortError())
    }
    signal.addEventListener('abort', cancel, { once: true })
  })
}
