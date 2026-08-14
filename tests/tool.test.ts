import { Context } from '@deepseek-ai/cordis'
import ToolRuntime from '@deepseek-ai/dsh-tools'
import SystemPrompt from '@deepseek-ai/dsh-system-prompt'
import { describe, expect, it } from 'vitest'
import type { ActionRequest, ActionResult, ComputerExecution, NativeStatus, ObserveRequest, ObservationResult } from '../src/contracts.js'
import { ComputerUseService } from '../src/service.js'
import { apply } from '../src/tool.js'

class FakeComputerUse extends ComputerUseService {
  constructor(ctx: Context) { super(ctx) }
  async observe(request: ObserveRequest, _execution: ComputerExecution): Promise<ObservationResult> {
    return { surface: request.surface, snapshotId: 's1', text: 'semantic observation', truncated: false, warnings: [] }
  }
  async action(request: ActionRequest, _execution: ComputerExecution): Promise<ActionResult> {
    return { surface: request.surface, action: request.action, status: 'ok', snapshotId: 's2', text: 'post state', truncated: false, warnings: [] }
  }
  async nativeStatus(): Promise<NativeStatus> {
    return { protocolVersion: 1, helperVersion: 'test', permissions: { accessibility: false, screenCapture: false, aquaSession: true, screenLocked: false } }
  }
}

describe('DSH tool plugin', () => {
  it('registers only the two text-first tools with model-safe schemas', async () => {
    const context = new Context()
    new SystemPrompt(context, {})
    new ToolRuntime(context)
    new FakeComputerUse(context)
    apply(context)

    const schemas = context.tools.schemas()
    expect(schemas.map((schema) => schema.name)).toEqual(['computer_observe', 'computer_action'])
    expect(JSON.stringify(schemas)).not.toContain('execute')
    expect(schemas[0]?.parameters).toMatchObject({ type: 'object' })
  })

  it('adds non-complete prompt guidance in the tool range', async () => {
    const context = new Context()
    new SystemPrompt(context, {})
    new ToolRuntime(context)
    new FakeComputerUse(context)
    apply(context)

    const assembly = await context.systemPrompt.assemble()
    const rendered = assembly.sections.map((section) => section.text).join('\n')
    expect(rendered).toContain('Computer use is text-first')
    expect(rendered).toContain('untrusted UI data')
  })
})
