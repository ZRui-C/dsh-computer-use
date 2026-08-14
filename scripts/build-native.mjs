import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const packageDir = path.join(root, 'native', 'macos-helper')
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'))
const binaryName = 'DSHComputerUse'
const appName = 'DSH Computer Use.app'
const distDir = path.join(packageDir, 'dist')
const app = path.join(distDir, appName)
const contents = path.join(app, 'Contents')
const macos = path.join(contents, 'MacOS')
const resources = path.join(contents, 'Resources')
const pluginResources = path.join(resources, 'Plugin')
const architectures = (process.env.COMPUTER_USE_ARCHS ?? 'arm64 x86_64')
  .split(/[ ,]+/)
  .filter(Boolean)

if (!fs.existsSync(path.join(root, 'dist', 'host.js'))) {
  execFileSync('pnpm', ['run', 'build:ts'], { cwd: root, stdio: 'inherit' })
}

const swiftArgs = ['build', '-c', 'release', '--package-path', packageDir]
for (const architecture of architectures) swiftArgs.push('--arch', architecture)
execFileSync('swift', swiftArgs, { stdio: 'inherit' })
const binPath = execFileSync('swift', [...swiftArgs, '--show-bin-path'], {
  encoding: 'utf8',
}).trim()
const binary = path.join(binPath, binaryName)
const plist = path.join(packageDir, 'App', 'Info.plist')
if (!fs.existsSync(binary)) throw new Error(`Swift build did not produce ${binary}`)
if (!fs.existsSync(plist)) throw new Error(`Missing app Info.plist template: ${plist}`)

fs.rmSync(distDir, { recursive: true, force: true })
fs.mkdirSync(macos, { recursive: true, mode: 0o755 })
fs.mkdirSync(pluginResources, { recursive: true, mode: 0o755 })
fs.copyFileSync(binary, path.join(macos, binaryName))
fs.chmodSync(path.join(macos, binaryName), 0o755)
fs.copyFileSync(plist, path.join(contents, 'Info.plist'))
execFileSync('/usr/bin/plutil', [
  '-replace', 'CFBundleVersion', '-string', manifest.version,
  path.join(contents, 'Info.plist'),
])
execFileSync('/usr/bin/plutil', [
  '-replace', 'CFBundleShortVersionString', '-string', manifest.version,
  path.join(contents, 'Info.plist'),
])

const iconPath = path.join(resources, 'AppIcon.icns')
execFileSync('swift', [
  path.join(root, 'scripts', 'generate-app-icon.swift'),
  iconPath,
  path.join(root, 'docs', 'assets', 'app-icon.png'),
], { stdio: 'inherit' })

fs.cpSync(path.join(root, 'dist'), path.join(pluginResources, 'dist'), { recursive: true })
for (const filename of [
  'cordis.patch.yml',
  'LICENSE',
  'THIRD_PARTY_NOTICES.md',
  'README.md',
  'README.zh.md',
]) {
  const source = path.join(root, filename)
  if (!fs.existsSync(source)) throw new Error(`Missing release resource: ${source}`)
  fs.copyFileSync(source, path.join(pluginResources, filename))
}
const releaseManifest = {
  name: manifest.name,
  version: manifest.version,
  description: manifest.description,
  license: manifest.license,
  repository: manifest.repository,
  homepage: manifest.homepage,
  bugs: manifest.bugs,
  type: manifest.type,
  exports: manifest.exports,
  dependencies: manifest.dependencies,
  peerDependencies: manifest.peerDependencies,
  engines: manifest.engines,
  dsh: manifest.dsh,
}
fs.writeFileSync(
  path.join(pluginResources, 'package.json'),
  `${JSON.stringify(releaseManifest, null, 2)}\n`,
)

const identity = process.env.COMPUTER_USE_CODESIGN_IDENTITY || '-'
const codesignArgs = ['--force', '--deep', '--options', 'runtime']
if (identity.startsWith('Developer ID Application:')) codesignArgs.push('--timestamp')
codesignArgs.push('--sign', identity, app)
execFileSync('/usr/bin/codesign', codesignArgs, { stdio: 'inherit' })
execFileSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', app], { stdio: 'inherit' })

const architectureInfo = execFileSync('/usr/bin/lipo', [
  '-info', path.join(macos, binaryName),
], { encoding: 'utf8' }).trim()
if (identity === '-') {
  process.stderr.write('warning: app is ad-hoc signed; public releases require Developer ID Application signing and notarization\n')
}
process.stdout.write(`${app}\n${architectureInfo}\n`)
