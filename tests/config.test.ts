import { describe, expect, it } from 'vitest'
import { resolveConfig } from '../src/config.js'

describe('OCR language configuration', () => {
  it('defaults to automatic language detection', () => {
    expect(resolveConfig().ocrLanguages).toEqual([])
  })

  it('preserves language preference order without sharing the caller array', () => {
    const languages = ['zh-Hans', 'en-US']
    const config = resolveConfig({ ocrLanguages: languages })
    languages.push('ja-JP')
    expect(config.ocrLanguages).toEqual(['zh-Hans', 'en-US'])
  })
})
