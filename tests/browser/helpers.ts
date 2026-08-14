import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { resolveConfig } from '../../src/config.js'
import { BrowserDriver, type BrowserDriverDeps } from '../../src/browser/index.js'
import type {
  ComputerExecution,
  ComputerSnapshot,
  SemanticNode,
} from '../../src/contracts.js'

export const CHROME_EXECUTABLE = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

export interface DriverFixture {
  driver: BrowserDriver
  stateDir: string
  workspaceRoot: string
  dispose: () => Promise<void>
}

export async function createDriver(deps: BrowserDriverDeps = {}): Promise<DriverFixture> {
  const stateDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'browser-driver-'))
  const workspaceRoot = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'browser-ws-'))
  const config = resolveConfig({
    chromeExecutablePath: CHROME_EXECUTABLE,
    headless: true,
    stateDir,
    actionSettleMs: 50,
  })
  const driver = new BrowserDriver(config, deps)
  return {
    driver,
    stateDir,
    workspaceRoot,
    dispose: async () => {
      await driver.dispose()
      await fs.promises.rm(stateDir, { recursive: true, force: true })
      await fs.promises.rm(workspaceRoot, { recursive: true, force: true })
    },
  }
}

export function makeExecution(
  sessionId: string,
  workspaceRoot: string,
  signal?: AbortSignal,
): ComputerExecution {
  return { sessionId, workspaceRoot, signal: signal ?? new AbortController().signal }
}

export function findNode(
  snapshot: ComputerSnapshot,
  predicate: (node: SemanticNode) => boolean,
): SemanticNode | undefined {
  return snapshot.nodes.find(predicate)
}

export function refOf(
  snapshot: ComputerSnapshot,
  role: string,
  name?: string,
): string {
  const node = snapshot.nodes.find((n) => {
    if (n.role !== role) return false
    if (name !== undefined && n.name !== name) return false
    return true
  })
  if (!node?.ref) {
    throw new Error(
      `no ref found for role=${role}${name !== undefined ? ` name=${name}` : ''}` +
        `; roles=[${snapshot.nodes
          .slice(0, 40)
          .map((n) => `${n.role}(${n.name ?? ''})`)
          .join(', ')}]`,
    )
  }
  return node.ref
}

/** True when any node leaks the given secret through name or value. */
export function leaksSecret(snapshot: ComputerSnapshot, secret: string): boolean {
  return snapshot.nodes.some((n) => n.name === secret || n.value === secret)
}
