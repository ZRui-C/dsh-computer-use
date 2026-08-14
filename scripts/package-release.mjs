import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'))
const app = path.join(root, 'native', 'macos-helper', 'dist', 'DSH Computer Use.app')
const releaseDir = path.join(root, 'release')
const dmg = path.join(releaseDir, `DSH-Computer-Use-${manifest.version}-universal.dmg`)
const skipNotarize = process.argv.includes('--skip-notarize')
const identity = process.env.COMPUTER_USE_CODESIGN_IDENTITY ?? ''

if (!fs.existsSync(app)) throw new Error(`Missing ${app}; run pnpm build first`)
exec('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', app])
const lipo = exec('/usr/bin/lipo', ['-archs', path.join(app, 'Contents', 'MacOS', 'DSHComputerUse')], true).trim()
if (!lipo.includes('arm64') || !lipo.includes('x86_64')) {
  throw new Error(`Release app must be Universal 2; found architectures: ${lipo}`)
}
if (!skipNotarize && !identity.startsWith('Developer ID Application:')) {
  throw new Error('release:macos requires COMPUTER_USE_CODESIGN_IDENTITY="Developer ID Application: ..."')
}

fs.mkdirSync(releaseDir, { recursive: true })
fs.rmSync(dmg, { force: true })
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-computer-use-release-'))
try {
  if (!skipNotarize) {
    const archive = path.join(temporary, 'DSH-Computer-Use.zip')
    exec('/usr/bin/ditto', ['-c', '-k', '--keepParent', app, archive])
    notarize(archive)
    exec('/usr/bin/xcrun', ['stapler', 'staple', app])
    exec('/usr/bin/xcrun', ['stapler', 'validate', app])
  }

  const staging = path.join(temporary, 'dmg')
  fs.mkdirSync(staging)
  exec('/usr/bin/ditto', [app, path.join(staging, 'DSH Computer Use.app')])
  fs.symlinkSync('/Applications', path.join(staging, 'Applications'))
  exec('/usr/bin/hdiutil', [
    'create',
    '-fs', 'HFS+',
    '-volname', 'DSH Computer Use',
    '-srcfolder', staging,
    '-format', 'UDZO',
    '-ov',
    dmg,
  ])
  if (identity) {
    const signArgs = ['--force']
    if (identity.startsWith('Developer ID Application:')) signArgs.push('--timestamp')
    signArgs.push('--sign', identity, dmg)
    exec('/usr/bin/codesign', signArgs)
  }
  if (!skipNotarize) {
    notarize(dmg)
    exec('/usr/bin/xcrun', ['stapler', 'staple', dmg])
    exec('/usr/bin/xcrun', ['stapler', 'validate', dmg])
    exec('/usr/sbin/spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg])
  }

  const checksum = exec('/usr/bin/shasum', ['-a', '256', dmg], true)
  fs.writeFileSync(`${dmg}.sha256`, checksum)
  process.stdout.write(`${dmg}\n${checksum}`)
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}

function notarize(file) {
  const profile = process.env.NOTARYTOOL_PROFILE
  if (profile) {
    exec('/usr/bin/xcrun', [
      'notarytool', 'submit', file,
      '--keychain-profile', profile,
      '--wait',
    ])
    return
  }
  const keyPath = process.env.APPLE_API_KEY_PATH
  const keyId = process.env.APPLE_API_KEY_ID
  const issuer = process.env.APPLE_API_ISSUER_ID
  if (!keyPath || !keyId || !issuer) {
    throw new Error('notarization requires NOTARYTOOL_PROFILE or APPLE_API_KEY_PATH/APPLE_API_KEY_ID/APPLE_API_ISSUER_ID')
  }
  exec('/usr/bin/xcrun', [
    'notarytool', 'submit', file,
    '--key', keyPath,
    '--key-id', keyId,
    '--issuer', issuer,
    '--wait',
  ])
}

function exec(command, args, capture = false) {
  return execFileSync(command, args, {
    cwd: root,
    encoding: capture ? 'utf8' : undefined,
    stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
  }) ?? ''
}
