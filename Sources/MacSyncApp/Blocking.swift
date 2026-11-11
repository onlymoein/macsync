import Foundation

/// Runs slow work that blocks (network, Homebrew, files) on its own background thread, not on
/// Swift's shared pool. Twenty icon downloads at once used to take every thread in that pool,
/// and then nothing else in MacSync could run: syncs, installs and the window all waited.
/// Starts straight away; `await x.value` gets the result.
final class Blocking<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: T?
    private var waiting: [CheckedContinuation<T, Never>] = []

    init(_ work: @escaping () -> T) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let value = work()
            lock.lock()
            result = value
            let waiters = waiting
            waiting = []
            lock.unlock()
            for waiter in waiters { waiter.resume(returning: value) }
        }
    }

    var value: T {
        get async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let result { lock.unlock(); continuation.resume(returning: result) } else { waiting.append(continuation); lock.unlock() }
            }
        }
    }
}
