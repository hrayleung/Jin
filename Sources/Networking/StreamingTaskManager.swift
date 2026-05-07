import Foundation

/// Streaming task manager for cancellation.
actor StreamingTaskManager {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    func register(id: UUID, task: Task<Void, Never>) {
        activeTasks[id] = task
    }

    func cancel(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
