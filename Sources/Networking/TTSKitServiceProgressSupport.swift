import Foundation

extension TTSKitService {
    nonisolated static func normalizedOptionalString(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }

    final class FirstAudioFrameGate: @unchecked Sendable {
        private let lock = NSLock()
        private var didEmitFirstAudioFrame = false

        func emitIfNeeded(_ action: () -> Void) {
            let shouldEmit = lock.withLock {
                guard !didEmitFirstAudioFrame else { return false }
                didEmitFirstAudioFrame = true
                return true
            }
            if shouldEmit {
                action()
            }
        }
    }

    final class AsyncProgressCallbackQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var tailTask: Task<Void, Never>?

        func enqueue(_ operation: @escaping @Sendable () async -> Void) {
            lock.withLock {
                let previousTask = tailTask
                let nextTask = Task {
                    _ = await previousTask?.result
                    await operation()
                }
                tailTask = nextTask
            }
        }

        func waitForCompletion() async {
            let task = lock.withLock { tailTask }
            _ = await task?.result
        }
    }
}
