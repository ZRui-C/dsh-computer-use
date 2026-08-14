import { Service, type Context } from '@deepseek-ai/cordis'
import type {
  ActionRequest,
  ActionResult,
  ComputerExecution,
  NativeStatus,
  ObserveRequest,
  ObservationResult,
} from './contracts.js'

export abstract class ComputerUseService extends Service {
  constructor(ctx: Context) {
    super(ctx, 'computerUse')
  }

  abstract observe(request: ObserveRequest, execution: ComputerExecution): Promise<ObservationResult>
  abstract action(request: ActionRequest, execution: ComputerExecution): Promise<ActionResult>
  abstract nativeStatus(signal?: AbortSignal): Promise<NativeStatus>
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    computerUse: ComputerUseService
  }
}
