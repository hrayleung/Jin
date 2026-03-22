import XCTest
@testable import Jin

final class SnapshotRecoveryHeuristicsTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AppSnapshotManager.clearAcceptedCurrentState()
    }

    func testNoHealthySnapshotDoesNotTriggerRecovery() {
        let current = SnapshotCoreCounts(
            conversations: 0,
            messages: 0,
            providers: 0,
            assistants: 0,
            mcpServers: 0
        )

        XCTAssertFalse(
            AppSnapshotManager.shouldTriggerRecovery(
                currentCounts: current,
                latestHealthySnapshot: nil
            )
        )
    }

    func testSeedLikeCurrentStateTriggersRecoveryAgainstHealthySnapshot() {
        let healthySnapshot = SnapshotManifest(
            id: "healthy",
            createdAt: Date(),
            reason: .launchHealthy,
            appVersion: "1.0.0",
            schemaVersion: 1,
            includesSecrets: true,
            isAutomatic: true,
            isHealthy: true,
            isLegacy: false,
            integrityDetail: "ok",
            counts: SnapshotCoreCounts(
                conversations: 12,
                messages: 150,
                providers: 5,
                assistants: 4,
                mcpServers: 3
            ),
            hasAttachments: true,
            hasPreferences: true,
            note: nil
        )

        let current = SnapshotCoreCounts(
            conversations: 0,
            messages: 0,
            providers: DefaultProviderSeeds.allProviders().count,
            assistants: 1,
            mcpServers: 0
        )

        XCTAssertTrue(
            AppSnapshotManager.shouldTriggerRecovery(
                currentCounts: current,
                latestHealthySnapshot: healthySnapshot
            )
        )
    }

    func testNonSeedLikeCurrentStateDoesNotTriggerRecovery() {
        let healthySnapshot = SnapshotManifest(
            id: "healthy",
            createdAt: Date(),
            reason: .launchHealthy,
            appVersion: "1.0.0",
            schemaVersion: 1,
            includesSecrets: true,
            isAutomatic: true,
            isHealthy: true,
            isLegacy: false,
            integrityDetail: "ok",
            counts: SnapshotCoreCounts(
                conversations: 12,
                messages: 150,
                providers: 5,
                assistants: 4,
                mcpServers: 3
            ),
            hasAttachments: true,
            hasPreferences: true,
            note: nil
        )

        let current = SnapshotCoreCounts(
            conversations: 8,
            messages: 80,
            providers: 5,
            assistants: 3,
            mcpServers: 2
        )

        XCTAssertFalse(
            AppSnapshotManager.shouldTriggerRecovery(
                currentCounts: current,
                latestHealthySnapshot: healthySnapshot
            )
        )
    }

    func testAcceptedCurrentStateSuppressesRecoveryPrompt() {
        let healthySnapshot = SnapshotManifest(
            id: "healthy",
            createdAt: Date(),
            reason: .launchHealthy,
            appVersion: "1.0.0",
            schemaVersion: 1,
            includesSecrets: true,
            isAutomatic: true,
            isHealthy: true,
            isLegacy: false,
            integrityDetail: "ok",
            counts: SnapshotCoreCounts(
                conversations: 12,
                messages: 150,
                providers: 5,
                assistants: 4,
                mcpServers: 3
            ),
            hasAttachments: true,
            hasPreferences: true,
            note: nil
        )

        let current = SnapshotCoreCounts(
            conversations: 0,
            messages: 0,
            providers: DefaultProviderSeeds.allProviders().count,
            assistants: 1,
            mcpServers: 0
        )

        AppSnapshotManager.recordAcceptedCurrentState(current)

        XCTAssertFalse(
            AppSnapshotManager.shouldTriggerRecovery(
                currentCounts: current,
                latestHealthySnapshot: healthySnapshot
            )
        )
    }
}
