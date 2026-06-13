import Foundation

enum PluginAutosave {
    /// Runs `persist` on the main actor after a debounce delay, unless the returned
    /// task is cancelled first. Callers store the task and cancel it before
    /// rescheduling / on disappear (exactly as the prior inline pattern did).
    static func schedule(
        delayNanos: UInt64 = 450_000_000,
        _ persist: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run { persist() }
        }
    }
}
