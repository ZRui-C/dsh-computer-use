export class ComputerUseError extends Error {
  readonly code: string

  constructor(code: string, message: string, options?: ErrorOptions) {
    super(message, options)
    this.name = 'ComputerUseError'
    this.code = code
  }
}

export function abortError(): ComputerUseError {
  return new ComputerUseError('ABORTED', 'computer use operation was cancelled')
}

export function throwIfAborted(signal: AbortSignal): void {
  if (signal.aborted) throw abortError()
}
