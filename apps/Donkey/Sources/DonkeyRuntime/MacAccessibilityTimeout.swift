import Foundation

enum MacAccessibilityTimeoutError: Error, Equatable, Sendable {
    case timedOut(timeoutNanoseconds: UInt64)
}

enum MacAccessibilityTimeout {
    static func run<T: Sendable>(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        guard timeoutNanoseconds > 0 else {
            return try operation()
        }

        let box = TimeoutContinuationBox<T>()
        return try await withCheckedThrowingContinuation { continuation in
            box.install(continuation)

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    box.resume(.success(try operation()))
                } catch {
                    box.resume(.failure(error))
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))
            ) {
                box.resume(.failure(
                    MacAccessibilityTimeoutError.timedOut(timeoutNanoseconds: timeoutNanoseconds)
                ))
            }
        }
    }
}

private final class TimeoutContinuationBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var didResume = false

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ result: Result<T, any Error>) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        lock.unlock()

        continuation.resume(with: result)
    }
}
