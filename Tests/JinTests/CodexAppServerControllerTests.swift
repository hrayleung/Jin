import XCTest
@testable import Jin

final class CodexAppServerControllerTests: XCTestCase {
    func testShutdownRootPIDsIgnoreUnmanagedCodexAppServers() {
        let snapshots = [
            CodexManagedProcessSnapshot(
                pid: 100,
                parentPID: 1,
                commandLine: "/usr/local/bin/codex app-server --listen ws://127.0.0.1:4500 JIN_MANAGED_CODEX_APP_SERVER=1"
            ),
            CodexManagedProcessSnapshot(
                pid: 101,
                parentPID: 1,
                commandLine: "/usr/local/bin/codex app-server --listen ws://127.0.0.1:5500"
            ),
            CodexManagedProcessSnapshot(
                pid: 102,
                parentPID: 100,
                commandLine: "node helper.js"
            )
        ]

        let rootPIDs = CodexAppServerController.shutdownRootPIDs(
            trackedPID: nil,
            includeDetectedRemainders: true,
            snapshots: snapshots
        )

        XCTAssertEqual(rootPIDs, [100])
    }

    func testShutdownRootPIDsIncludeTrackedPIDAlongsideManagedRemainders() {
        let snapshots = [
            CodexManagedProcessSnapshot(
                pid: 100,
                parentPID: 1,
                commandLine: "/usr/local/bin/codex app-server --listen ws://127.0.0.1:4500 JIN_MANAGED_CODEX_APP_SERVER=1"
            )
        ]

        let rootPIDs = CodexAppServerController.shutdownRootPIDs(
            trackedPID: 200,
            includeDetectedRemainders: true,
            snapshots: snapshots
        )

        XCTAssertEqual(rootPIDs, [100, 200])
    }
}
