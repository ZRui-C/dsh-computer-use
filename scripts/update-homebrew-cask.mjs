#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises'
import process from 'node:process'

const [caskPath, version, sha256] = process.argv.slice(2)

if (caskPath === undefined || version === undefined || sha256 === undefined) {
  throw new Error('usage: node scripts/update-homebrew-cask.mjs <cask-path> <version> <sha256>')
}
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
  throw new Error(`invalid release version: ${version}`)
}
if (!/^[a-f0-9]{64}$/.test(sha256)) {
  throw new Error(`invalid SHA-256 digest: ${sha256}`)
}

const original = await readFile(caskPath, 'utf8')
let updated = replaceSingle(original, /^  version "[^"]+"$/gm, `  version "${version}"`, 'version')
updated = replaceSingle(updated, /^  sha256 "[a-f0-9]{64}"$/gm, `  sha256 "${sha256}"`, 'sha256')

if (updated === original) {
  process.stdout.write(`Homebrew Cask is already at ${version}.\n`)
} else {
  await writeFile(caskPath, updated)
  process.stdout.write(`Updated Homebrew Cask to ${version}.\n`)
}

function replaceSingle(source, pattern, replacement, field) {
  const matches = [...source.matchAll(pattern)]
  if (matches.length !== 1) {
    throw new Error(`expected exactly one ${field} field in Cask, found ${matches.length}`)
  }
  return source.replace(pattern, replacement)
}
