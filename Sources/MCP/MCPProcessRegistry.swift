import Foundation

/// Tracks every live MCP child process so app termination can reap them.
///
/// `Process` does not kill its child when the parent exits, and
/// `applicationWillTerminate` is synchronous, so it cannot await the actor-
/// isolated `MCPClient.stop()` teardown. This registry gives the app delegate
/// a lock-protected, synchronous handle on the raw processes: clients register
/// on launch, the process's own `terminationHandler` unregisters on any exit
/// (normal, crash, or `stop()`), and `terminateAll()` sweeps whatever is still
/// running at quit.
final class MCPProcessRegistry: @unchecked Sendable {
    static let shared = MCPProcessRegistry()

    private let lock = NSLock()
    private var processesByID: [ObjectIdentifier: Process] = [:]

    func register(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processesByID[ObjectIdentifier(process)] = process
    }

    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processesByID.removeValue(forKey: ObjectIdentifier(process))
    }

    func terminateAll() {
        lock.lock()
        let processes = Array(processesByID.values)
        processesByID.removeAll()
        lock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }
    }
}
