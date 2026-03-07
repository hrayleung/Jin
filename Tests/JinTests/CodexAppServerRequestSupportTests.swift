import XCTest
@testable import Jin

final class CodexAppServerRequestSupportTests: XCTestCase {
    func testThreadStartParamsUseSafeDefaults() {
        let params = CodexAppServerRequestBuilder.threadStartParams(
            modelID: "gpt-5-codex",
            controls: GenerationControls()
        )

        XCTAssertEqual(params["model"] as? String, "gpt-5-codex")
        XCTAssertEqual(params["approvalPolicy"] as? String, "never")
        XCTAssertEqual(params["sandbox"] as? String, CodexSandboxMode.workspaceWrite.rawValue)
        XCTAssertEqual(params["persistExtendedHistory"] as? Bool, false)
    }


    func testThreadResumeParamsMirrorSafeDefaults() {
        var controls = GenerationControls()
        controls.codexSandboxMode = .readOnly
        controls.codexPersonality = .friendly
        controls.codexWorkingDirectory = "/tmp/repo"

        let params = CodexAppServerRequestBuilder.threadResumeParams(
            threadID: "remote-thread-1",
            modelID: "gpt-5-codex",
            controls: controls
        )

        XCTAssertEqual(params["threadId"] as? String, "remote-thread-1")
        XCTAssertEqual(params["model"] as? String, "gpt-5-codex")
        XCTAssertEqual(params["approvalPolicy"] as? String, "never")
        XCTAssertEqual(params["sandbox"] as? String, CodexSandboxMode.readOnly.rawValue)
        XCTAssertEqual(params["persistExtendedHistory"] as? Bool, false)
        XCTAssertEqual(params["personality"] as? String, CodexPersonality.friendly.rawValue)
        XCTAssertEqual(params["cwd"] as? String, "/tmp/repo")
    }
    func testTurnStartParamsIncludeSandboxPolicyAndReasoningSummary() throws {
        var controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high, summary: ReasoningSummary.none)
        )
        controls.codexWorkingDirectory = "/tmp/project"
        controls.codexSandboxMode = .readOnly
        controls.codexPersonality = .pragmatic

        let params = CodexAppServerRequestBuilder.turnStartParams(
            threadID: "thread-1",
            inputItems: [[
                "type": "text",
                "text": "Fix the failing test",
                "text_elements": [Any]()
            ]],
            modelID: "gpt-5-codex",
            controls: controls
        )

        XCTAssertEqual(params["approvalPolicy"] as? String, "never")
        XCTAssertEqual(params["cwd"] as? String, "/tmp/project")
        XCTAssertEqual(params["personality"] as? String, CodexPersonality.pragmatic.rawValue)
        XCTAssertEqual(params["effort"] as? String, ReasoningEffort.high.rawValue)
        XCTAssertEqual(params["summary"] as? String, ReasoningSummary.none.rawValue)

        let sandboxPolicy = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])
        XCTAssertEqual(sandboxPolicy["type"] as? String, "readOnly")
    }

    func testAutoReplyDeclinesApprovalRequests() {
        XCTAssertEqual(
            CodexAppServerAutoReply.result(forServerRequestMethod: "item/commandExecution/requestApproval")?["decision"] as? String,
            "decline"
        )
        XCTAssertEqual(
            CodexAppServerAutoReply.result(forServerRequestMethod: "item/fileChange/requestApproval")?["decision"] as? String,
            "decline"
        )
        XCTAssertEqual(
            CodexAppServerAutoReply.result(forServerRequestMethod: "execCommandApproval")?["decision"] as? String,
            "denied"
        )
        XCTAssertNil(CodexAppServerAutoReply.result(forServerRequestMethod: "item/tool/requestUserInput"))
    }
}
