import { abortError, throwIfAborted } from './errors.js'

interface Waiter {
  resolve: (release: () => void) => void
  reject: (error: Error) => void
  signal?: AbortSignal
  onAbort?: () => void
}

export class AbortableMutex {
  private locked = false
  private readonly queue: Waiter[] = []

  async acquire(signal?: AbortSignal): Promise<() => void> {
    if (signal !== undefined) throwIfAborted(signal)
    if (!this.locked) {
      this.locked = true
      return this.releaseOnce()
    }

    return await new Promise<() => void>((resolve, reject) => {
      const waiter: Waiter = { resolve, reject, ...(signal === undefined ? {} : { signal }) }
      if (signal !== undefined) {
        waiter.onAbort = () => {
          const index = this.queue.indexOf(waiter)
          if (index >= 0) this.queue.splice(index, 1)
          reject(abortError())
        }
        signal.addEventListener('abort', waiter.onAbort, { once: true })
      }
      this.queue.push(waiter)
    })
  }

  async run<T>(operation: () => Promise<T>, signal?: AbortSignal): Promise<T> {
    const release = await this.acquire(signal)
    try {
      return await operation()
    } finally {
      release()
    }
  }

  private releaseOnce(): () => void {
    let released = false
    return () => {
      if (released) return
      released = true
      while (this.queue.length > 0) {
        const waiter = this.queue.shift()!
        if (waiter.signal?.aborted) continue
        if (waiter.signal !== undefined && waiter.onAbort !== undefined) {
          waiter.signal.removeEventListener('abort', waiter.onAbort)
        }
        waiter.resolve(this.releaseOnce())
        return
      }
      this.locked = false
    }
  }
}
