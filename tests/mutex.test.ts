import { describe, expect, it } from 'vitest'
import { AbortableMutex } from '../src/mutex.js'

const deferred = <T>() => {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((done) => { resolve = done })
  return { promise, resolve }
}

describe('AbortableMutex', () => {
  it('serializes operations', async () => {
    const mutex = new AbortableMutex()
    const gate = deferred<void>()
    const order: string[] = []
    const first = mutex.run(async () => {
      order.push('first:start')
      await gate.promise
      order.push('first:end')
    })
    const second = mutex.run(async () => { order.push('second') })
    await Promise.resolve()
    expect(order).toEqual(['first:start'])
    gate.resolve()
    await Promise.all([first, second])
    expect(order).toEqual(['first:start', 'first:end', 'second'])
  })

  it('removes an aborted waiter', async () => {
    const mutex = new AbortableMutex()
    const release = await mutex.acquire()
    const controller = new AbortController()
    const waiting = mutex.acquire(controller.signal)
    controller.abort()
    await expect(waiting).rejects.toThrow(/cancelled/)
    release()
    const next = await mutex.acquire()
    next()
  })
})
