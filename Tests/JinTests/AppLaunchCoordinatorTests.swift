import Foundation
import XCTest
@testable import Jin

final class AppLaunchCoordinatorTests: PreferencesSandboxedTestCase {
    private var previousAppSupportRoot: String?
    private var previousSnapshotsSuspended = false
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        previousAppSupportRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        previousSnapshotsSuspended = AppRuntimeProtection.automaticSnapshotsSuspended
        AppRuntimeProtection.automaticSnapshotsSuspended = false

        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)

        AppSnapshotManager.clearAcceptedCurrentState()
        try AppDataLocations.ensureDirectoriesExist()
    }

    override func tearDownWithError() throws {
        AppRuntimeProtection.automaticSnapshotsSuspended = previousSnapshotsSuspended
        AppSnapshotManager.clearAcceptedCurrentState()

        if let previousAppSupportRoot {
            setenv("JIN_APP_SUPPORT_ROOT", previousAppSupportRoot, 1)
        } else {
            unsetenv("JIN_APP_SUPPORT_ROOT")
        }

        try? FileManager.default.removeItem(at: temporaryRoot)

        try super.tearDownWithError()
    }

    @MainActor
    func testHealthyFirstLaunchIsReadyWithoutWaitingForAppear() {
        let coordinator = AppLaunchCoordinator()

        guard case .ready = coordinator.phase else {
            XCTFail("Healthy first launch should be ready before the first window paint.")
            return
        }

        coordinator.startIfNeeded()
        guard case .ready = coordinator.phase else {
            XCTFail("startIfNeeded() must not restart a launch that already resolved.")
            return
        }
    }
}
