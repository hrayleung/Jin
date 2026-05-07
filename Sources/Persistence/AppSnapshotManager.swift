import Foundation
import SwiftData

enum AppSnapshotManager {
    private static let acceptedCurrentStateDefaultsKey = "recovery.acceptedCurrentState"

    static func evaluateCurrentStoreForStartup() throws -> StartupStoreEvaluation {
        try AppDataLocations.migrateLegacyDataIfNeeded()
        migrateLegacySnapshotsIfNeeded()

        if let queuedRestoreError = applyQueuedRestoreIfPresent() {
            NSLog("Jin recovery warning: %@", queuedRestoreError)
        }

        let storeURL = try AppDataLocations.storeURL()

        if FileManager.default.fileExists(atPath: storeURL.path) {
            let integrity = SQLiteDatabaseSupport.quickCheck(at: storeURL)

            if integrity.passed {
                do {
                    let container = try PersistenceContainerFactory.makeContainer(storeURL: storeURL)
                    let currentCounts = PersistenceContainerFactory.fetchCoreCounts(in: container)
                    let latestHealthy = latestHealthySnapshot()

                    if shouldTriggerRecovery(currentCounts: currentCounts, latestHealthySnapshot: latestHealthy?.manifest) {
                        let snapshots = listSnapshots()
                        return .recovery(
                            StartupRecoveryState(
                                issueDescription: "Jin detected possible data loss. The current database has \(currentCounts.total) items, but a recent snapshot has \(latestHealthy!.manifest.counts.total).",
                                snapshots: snapshots,
                                canContinueCurrentState: true
                            ),
                            container
                        )
                    }

                    return .ready(container)
                } catch {
                    NSLog("Jin startup warning: store failed to open: %@", error.localizedDescription)
                    let snapshots = listSnapshots()
                    if snapshots.contains(where: { $0.manifest.isHealthy }) {
                        return .recovery(
                            StartupRecoveryState(
                                issueDescription: "Jin could not open the database: \(error.localizedDescription)",
                                snapshots: snapshots,
                                canContinueCurrentState: false
                            ),
                            nil
                        )
                    }
                }
            } else {
                NSLog("Jin startup warning: integrity check failed: %@", integrity.detail)
                let snapshots = listSnapshots()
                if snapshots.contains(where: { $0.manifest.isHealthy }) {
                    return .recovery(
                        StartupRecoveryState(
                            issueDescription: "Jin's database failed its integrity check: \(integrity.detail)",
                            snapshots: snapshots,
                            canContinueCurrentState: false
                        ),
                        nil
                    )
                }
            }

            NSLog("Jin startup warning: no healthy snapshots available, starting fresh.")
        }

        SQLiteDatabaseSupport.removeStoreArtifacts(at: storeURL)
        clearAcceptedCurrentState()
        return .ready(try PersistenceContainerFactory.makeContainer(storeURL: storeURL))
    }

    static func shouldTriggerRecovery(
        currentCounts: SnapshotCoreCounts,
        latestHealthySnapshot: SnapshotManifest?
    ) -> Bool {
        guard let latestHealthySnapshot else { return false }
        guard latestHealthySnapshot.counts.total > 0 else { return false }
        if acceptedCurrentStateMatches(currentCounts) {
            return false
        }
        return currentCounts.isEmpty || currentCounts.isSeedLike
    }

    static func recordAcceptedCurrentState(_ counts: SnapshotCoreCounts) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: acceptedCurrentStateDefaultsKey)
    }

    static func clearAcceptedCurrentState() {
        UserDefaults.standard.removeObject(forKey: acceptedCurrentStateDefaultsKey)
    }

    private static func acceptedCurrentStateMatches(_ counts: SnapshotCoreCounts) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: acceptedCurrentStateDefaultsKey),
              let accepted = try? JSONDecoder().decode(SnapshotCoreCounts.self, from: data) else {
            return false
        }
        return accepted == counts
    }
}
