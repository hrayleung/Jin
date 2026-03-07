import XCTest
@testable import Jin

final class CodexManagedProcessSupportTests: XCTestCase {
    func testParseProcessSnapshotExtractsPIDParentAndCommand() {
        let raw = "  123   1 /Users/test/.npm-global/bin/codex app-server --listen ws://127.0.0.1:4500 JIN_MANAGED_CODEX_APP_SERVER=1\n"
        let snapshots = CodexManagedProcessSupport.parseProcessSnapshot(raw)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].pid, 123)
        XCTAssertEqual(snapshots[0].parentPID, 1)
        XCTAssertTrue(snapshots[0].commandLine.contains("codex app-server"))
    }

    func testManagedRootPIDsFiltersToJinManagedCodexCommands() {
        let snapshots = [
            CodexManagedProcessSnapshot(
                pid: 100,
                parentPID: 1,
                commandLine: "/usr/local/bin/codex app-server --listen ws://127.0.0.1:4500 JIN_MANAGED_CODEX_APP_SERVER=1"
            ),
            CodexManagedProcessSnapshot(
                pid: 101,
                parentPID: 1,
                commandLine: "/usr/local/bin/codex app-server --listen ws://127.0.0.1:4500"
            ),
            CodexManagedProcessSnapshot(
                pid: 102,
                parentPID: 100,
                commandLine: "node helper.js JIN_MANAGED_CODEX_APP_SERVER=1"
            )
        ]

        XCTAssertEqual(CodexManagedProcessSupport.managedRootPIDs(in: snapshots), [100])
    }

    func testShutdownOrderReturnsChildrenBeforeParents() {
        let snapshots = [
            CodexManagedProcessSnapshot(pid: 200, parentPID: 1, commandLine: "codex app-server JIN_MANAGED_CODEX_APP_SERVER=1"),
            CodexManagedProcessSnapshot(pid: 201, parentPID: 200, commandLine: "child one"),
            CodexManagedProcessSnapshot(pid: 202, parentPID: 201, commandLine: "grandchild"),
            CodexManagedProcessSnapshot(pid: 203, parentPID: 200, commandLine: "child two")
        ]

        let ordered = CodexManagedProcessSupport.shutdownOrder(for: [200], snapshots: snapshots)
        guard let index200 = ordered.firstIndex(of: 200),
              let index201 = ordered.firstIndex(of: 201),
              let index202 = ordered.firstIndex(of: 202),
              let index203 = ordered.firstIndex(of: 203) else {
            return XCTFail("Expected all pids in shutdown order")
        }

        XCTAssertLessThan(index202, index201)
        XCTAssertLessThan(index201, index200)
        XCTAssertLessThan(index203, index200)
    }
}
