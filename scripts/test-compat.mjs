import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Separate dependency trees prevent the primary checkout's alpha packages from
// making an older-runtime compatibility test pass accidentally.
const families = {
  '0.1.0-rc.6': { cordis: '4.0.1', schemastery: '3.18.1' },
  '0.2.0-rc.2': { cordis: '4.0.4', schemastery: '3.18.4' },
  '0.2.1-alpha.1': { cordis: '4.0.5-alpha.1', schemastery: '3.18.5-alpha.1' },
}
const version = process.argv[2]
const family = families[version]
if (!family) throw new Error(`Choose an explicit DSH test family: ${Object.keys(families).join(', ')}`)
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'computer-use-compat-'))
try {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'))
  delete manifest.scripts.prepare
  for (const name of Object.keys(manifest.devDependencies)) {
    if (name.startsWith('@deepseek-ai/dsh-')) manifest.devDependencies[name] = version
  }
  if (version === '0.1.0-rc.6') {
    // rc.6 published caret peers otherwise select newer rc.8 packages with a
    // different agent peer. Pin its known peer closure; do not ignore peers.
    for (const name of ['attachment', 'brand', 'code-runtime', 'invariants', 'llm',
      'scope', 'session', 'timeout', 'typert-protocol', 'user-approval']) {
      manifest.devDependencies[`@deepseek-ai/dsh-${name}`] = version
    }
  }
  manifest.devDependencies['@deepseek-ai/cordis'] = family.cordis
  manifest.devDependencies['@deepseek-ai/schemastery'] = family.schemastery
  fs.writeFileSync(path.join(fixture, 'package.json'), `${JSON.stringify(manifest, null, 2)}\n`)
  for (const name of ['src', 'tests', 'tsconfig.json', 'tsconfig.build.json', 'vitest.config.ts']) {
    fs.cpSync(path.join(root, name), path.join(fixture, name), { recursive: true })
  }
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm'
  const run = (command, args) => execFileSync(command, args, { cwd: fixture, stdio: 'inherit' })
  run(npm, ['install', '--ignore-scripts', '--no-audit', '--no-fund', '--package-lock=false', '--registry=https://registry.npmjs.org/'])
  run(process.execPath, ['node_modules/typescript/bin/tsc', '-p', 'tsconfig.json', '--noEmit'])
  run(process.execPath, ['node_modules/typescript/bin/tsc', '-p', 'tsconfig.build.json'])
  run(process.execPath, ['node_modules/vitest/vitest.mjs', 'run', '--exclude', 'tests/browser/**'])
  process.stdout.write(`DSH ${version}: typecheck, build and non-browser contract tests passed\n`)
} finally {
  fs.rmSync(fixture, { recursive: true, force: true })
}
