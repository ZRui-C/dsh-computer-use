import fs from 'node:fs/promises'

export async function ensurePrivateDirectory(path: string): Promise<void> {
  await fs.mkdir(path, { recursive: true, mode: 0o700 })
  await fs.chmod(path, 0o700).catch(() => undefined)
}
