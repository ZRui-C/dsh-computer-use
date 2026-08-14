export class MonotonicIds {
  private counter = 0

  constructor(private readonly prefix: string) {}

  next(): string {
    this.counter += 1
    return `${this.prefix}${this.counter.toString(36)}`
  }
}
