import Foundation

struct CodexAppServerShutdownOutcome {
    let remainingPIDs: [Int32]
    let managedProcessCount: Int
    let force: Bool
}

enum CodexAppServerShutdownSupport {
    nonisolated static func performShutdown(
        trackedPID: Int32?,
        includeDetectedRemainders: Bool,
        force: Bool
    ) -> CodexAppServerShutdownOutcome {
        let snapshots = CodexManagedProcessSupport.currentProcessSnapshots()
        let rootPIDs = shutdownRootPIDs(
            trackedPID: trackedPID,
            includeDetectedRemainders: includeDetectedRemainders,
            snapshots: snapshots
        )

        let aliveRoots = rootPIDs.filter(CodexManagedProcessSupport.isProcessAlive)
        guard !aliveRoots.isEmpty else {
            let remainingManaged = CodexManagedProcessSupport.managedRootPIDs(in: snapshots).count
            return CodexAppServerShutdownOutcome(
                remainingPIDs: [],
                managedProcessCount: remainingManaged,
                force: force
            )
        }

        let orderedPIDs = CodexManagedProcessSupport.shutdownOrder(for: aliveRoots, snapshots: snapshots)

        if force {
            CodexManagedProcessSupport.signal(orderedPIDs, signal: SIGKILL)
            _ = CodexManagedProcessSupport.waitForExit(of: Array(aliveRoots), timeout: 0.2)
        } else {
            CodexManagedProcessSupport.signal(orderedPIDs, signal: SIGINT)

            if !CodexManagedProcessSupport.waitForExit(of: Array(aliveRoots), timeout: 0.8) {
                CodexManagedProcessSupport.signal(orderedPIDs, signal: SIGTERM)
            }

            if !CodexManagedProcessSupport.waitForExit(of: Array(aliveRoots), timeout: 0.35) {
                CodexManagedProcessSupport.signal(orderedPIDs, signal: SIGKILL)
            }
        }

        let refreshedSnapshots = CodexManagedProcessSupport.currentProcessSnapshots()
        let remaining = CodexManagedProcessSupport.alivePIDs(in: Array(aliveRoots))
        let remainingManaged = CodexManagedProcessSupport.managedRootPIDs(in: refreshedSnapshots).count
        return CodexAppServerShutdownOutcome(
            remainingPIDs: remaining,
            managedProcessCount: remainingManaged,
            force: force
        )
    }

    nonisolated static func shutdownRootPIDs(
        trackedPID: Int32?,
        includeDetectedRemainders: Bool,
        snapshots: [CodexManagedProcessSnapshot]
    ) -> Set<Int32> {
        var rootPIDs = Set<Int32>()

        if let trackedPID, trackedPID > 0 {
            rootPIDs.insert(trackedPID)
        }
        if includeDetectedRemainders {
            rootPIDs.formUnion(CodexManagedProcessSupport.managedRootPIDs(in: snapshots))
        }

        return rootPIDs
    }
}
