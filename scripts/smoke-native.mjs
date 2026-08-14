import fs from 'node:fs/promises'
import net from 'node:net'
import path from 'node:path'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { fileURLToPath } from 'node:url'

const execFileAsync = promisify(execFile)
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const app = path.join(root, 'native/macos-helper/dist/DSH Computer Use.app')
const socketPath = `/tmp/dsh-computer-use-smoke-${process.pid}.sock`
const screenshotPath = `/tmp/dsh-computer-use-smoke-${process.pid}.png`

await fs.rm(socketPath, { force: true })
await fs.rm(screenshotPath, { force: true })
await execFileAsync('/usr/bin/open', ['-gjn', app, '--args', '--agent', '--socket', socketPath])

let socket
for (let attempt = 0; attempt < 50; attempt += 1) {
  try {
    socket = await connect(socketPath)
    break
  } catch {
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
}
if (!socket) throw new Error('native helper socket did not become available')

let buffer = ''
let id = 0
const pending = new Map()
socket.setEncoding('utf8')
socket.on('data', (chunk) => {
  buffer += chunk
  while (true) {
    const newline = buffer.indexOf('\n')
    if (newline < 0) break
    const line = buffer.slice(0, newline)
    buffer = buffer.slice(newline + 1)
    if (!line) continue
    const response = JSON.parse(line)
    const handler = pending.get(response.id)
    if (handler) {
      pending.delete(response.id)
      response.ok ? handler.resolve(response.result) : handler.reject(new Error(`${response.error?.code}: ${response.error?.message}`))
    }
  }
})

function request(method, params = {}) {
  const requestId = `smoke-${++id}`
  return new Promise((resolve, reject) => {
    pending.set(requestId, { resolve, reject })
    socket.write(`${JSON.stringify({ id: requestId, method, params })}\n`)
  })
}

try {
  const handshake = await request('handshake', { protocolVersion: 1 })
  const status = await request('status')
  const observation = await request('observeDesktop', {
    maxNodes: 30,
    ocr: 'always',
    screenshotPath,
  })
  if (handshake.protocolVersion !== 1) throw new Error(`unexpected protocol ${handshake.protocolVersion}`)
  if (typeof status.permissions?.accessibility !== 'boolean') throw new Error('status permissions shape is invalid')
  if (!Array.isArray(observation.nodes)) throw new Error('observation nodes are missing')
  const screenshotBytes = await fs.stat(screenshotPath).then((stat) => stat.size).catch(() => 0)
  if (status.permissions.screenCapture && screenshotBytes === 0) throw new Error('screen capture is granted but no screenshot was written')
  console.log(JSON.stringify({
    protocolVersion: handshake.protocolVersion,
    helperVersion: handshake.helperVersion,
    permissions: status.permissions,
    nodes: observation.nodes.length,
    axNodes: observation.nodes.filter((node) => node.source === 'ax').length,
    ocrNodes: observation.nodes.filter((node) => node.source === 'ocr').length,
    screenshotBytes,
    warnings: observation.warnings,
  }))
  await request('shutdown')
} finally {
  socket.destroy()
  await new Promise((resolve) => setTimeout(resolve, 300))
  await fs.rm(socketPath, { force: true })
  await fs.rm(screenshotPath, { force: true })
}

function connect(target) {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(target)
    client.once('connect', () => resolve(client))
    client.once('error', reject)
  })
}
