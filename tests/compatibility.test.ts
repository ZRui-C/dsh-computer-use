import fs from 'node:fs'
import { describe, expect, it } from 'vitest'

const manifest = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8')) as {
  peerDependencies: Record<string, string>
}

describe('published runtime compatibility declarations', () => {
  it.each(['0.2.0-rc.2', '0.2.1-alpha.1'])('explicitly accepts verified prerelease %s', (version) => {
    const peers = Object.entries(manifest.peerDependencies).filter(([name]) => name.startsWith('@deepseek-ai/dsh-'))
    expect(peers).toHaveLength(4)
    for (const [, range] of peers) {
      // A caret beginning at 0.1.0-rc.6 excludes these different prerelease tuples.
      expect(range.split(/\s*\|\|\s*/)).toContain(version)
      expect(range).not.toContain('*')
    }
  })
})
