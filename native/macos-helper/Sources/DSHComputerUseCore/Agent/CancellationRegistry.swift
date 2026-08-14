import Foundation

/// A thread-safe set of request ids that have been asked to cancel.
///
/// Long-running actions (for example `wait` and `drag`) poll this registry so
/// cancellation is honored where practical. The registry is cleared once the
/// request completes.
public final class CancellationRegistry {
    private let lock = NSLock()
    private var cancelled: Set<String> = []

    public init() {}

    public func cancel(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        cancelled.insert(id)
    }

    public func isCancelled(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled.contains(id)
    }

    public func clear(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        cancelled.remove(id)
    }
}
