import { expect, it } from 'vitest'
import { MonotonicIds } from '../src/ids.js'

it('produces compact monotonic ids', () => {
  const ids = new MonotonicIds('s')
  expect([ids.next(), ids.next(), ids.next()]).toEqual(['s1', 's2', 's3'])
})
