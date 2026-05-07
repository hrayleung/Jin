import XCTest
@testable import Jin

final class AgentToolApprovalSupportTests: XCTestCase {
    func testAgentToolNeedsApprovalUsesCommandAliasForAllowlist() async {
        var controls = AgentModeControls()
        controls.allowedCommandPrefixes = ["pwd"]

        let needsApproval = await AgentToolApprovalSupport.needsApproval(
            functionName: AgentToolHub.shellExecuteFunctionName,
            arguments: ["cmd": AnyCodable(" pwd ")],
            controls: controls,
            approvalKey: nil,
            approvalStore: AgentApprovalSessionStore()
        )

        XCTAssertFalse(needsApproval)
    }

    func testMakeAgentApprovalRequestUsesShellAliases() {
        let request = AgentToolApprovalSupport.makeRequest(
            functionName: AgentToolHub.shellExecuteFunctionName,
            arguments: [
                "cmd": AnyCodable(" pwd "),
                "cwd": AnyCodable(" /repo ")
            ],
            controls: AgentModeControls()
        )

        guard case .shellCommand(let command, let cwd) = request.kind else {
            return XCTFail("Expected shell command approval request")
        }
        XCTAssertEqual(command, "pwd")
        XCTAssertEqual(cwd, "/repo")
    }

    func testMakeAgentApprovalRequestUsesFileWriteAliasesAndPreservesPreviewSpacing() {
        let request = AgentToolApprovalSupport.makeRequest(
            functionName: AgentToolHub.fileWriteFunctionName,
            arguments: [
                "file": AnyCodable(" README.md "),
                "text": AnyCodable("  keep spacing\n")
            ],
            controls: AgentModeControls()
        )

        guard case .fileWrite(let path, let preview) = request.kind else {
            return XCTFail("Expected file write approval request")
        }
        XCTAssertEqual(path, "README.md")
        XCTAssertEqual(preview, "  keep spacing\n")
    }

    func testMakeAgentApprovalRequestUsesFileEditAliasesAndPreservesPreviewSpacing() {
        let request = AgentToolApprovalSupport.makeRequest(
            functionName: AgentToolHub.fileEditFunctionName,
            arguments: [
                "file_path": AnyCodable(" Sources/App.swift "),
                "search": AnyCodable("  old\n"),
                "replace": AnyCodable("  new\n")
            ],
            controls: AgentModeControls()
        )

        guard case .fileEdit(let path, let oldText, let newText) = request.kind else {
            return XCTFail("Expected file edit approval request")
        }
        XCTAssertEqual(path, "Sources/App.swift")
        XCTAssertEqual(oldText, "  old\n")
        XCTAssertEqual(newText, "  new\n")
    }
}
