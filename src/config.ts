import os from 'node:os'
import path from 'node:path'
import z from '@deepseek-ai/schemastery'
import {
  DEFAULT_MAX_NODES,
  DEFAULT_MAX_OBSERVATION_CHARS,
} from './contracts.js'

export interface ComputerUseConfig {
  chromeExecutablePath?: string
  headless?: boolean
  stateDir?: string
  helperAppPath?: string
  helperSocketPath?: string
  maxObservationChars?: number
  maxNodes?: number
  actionSettleMs?: number
}

export interface ResolvedComputerUseConfig {
  chromeExecutablePath: string
  headless: boolean
  stateDir: string
  helperAppPath?: string
  helperSocketPath: string
  maxObservationChars: number
  maxNodes: number
  actionSettleMs: number
}

const defaultStateDir = path.join(os.homedir(), '.dsh', 'computer-use')

export const Config: z<ComputerUseConfig> = z.object({
  chromeExecutablePath: z.string().default('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'),
  headless: z.boolean().default(false),
  stateDir: z.string().default(defaultStateDir),
  helperAppPath: z.string(),
  helperSocketPath: z.string().default(path.join(defaultStateDir, 'native-agent.sock')),
  maxObservationChars: z.number().step(1).min(2_000).max(100_000).default(DEFAULT_MAX_OBSERVATION_CHARS),
  maxNodes: z.number().step(1).min(20).max(2_000).default(DEFAULT_MAX_NODES),
  actionSettleMs: z.number().step(1).min(0).max(10_000).default(300),
})

export function resolveConfig(config: ComputerUseConfig = {}): ResolvedComputerUseConfig {
  return {
    chromeExecutablePath:
      config.chromeExecutablePath ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: config.headless ?? false,
    stateDir: config.stateDir ?? defaultStateDir,
    ...(config.helperAppPath === undefined ? {} : { helperAppPath: config.helperAppPath }),
    helperSocketPath: config.helperSocketPath ?? path.join(config.stateDir ?? defaultStateDir, 'native-agent.sock'),
    maxObservationChars: config.maxObservationChars ?? DEFAULT_MAX_OBSERVATION_CHARS,
    maxNodes: config.maxNodes ?? DEFAULT_MAX_NODES,
    actionSettleMs: config.actionSettleMs ?? 300,
  }
}
