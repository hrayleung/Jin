import XCTest
@testable import Jin

final class CodexAppServerInteractionSupportTests: XCTestCase {
    func testInteractionRequestParsesCommandApproval() throws {
        let params = try TestJSONHelpers.makeJSONObject([
            "threadId": "thread-1",
            "turnId": "turn-1",
            "itemId": "item-1",
            "command": "git status",
            "cwd": "/tmp/repo",
            "reason": "Needs to inspect the working tree.",
            "commandActions": [
                [
                    "type": "read",
                    "command": "git status",
                    "name": "Git status",
                    "path": "/tmp/repo"
                ]
            ]
        ])

        let request = try XCTUnwrap(
            CodexAppServerAdapter.interactionRequest(
                id: .int(1),
                method: "item/commandExecution/requestApproval",
                params: params
            )
        )

        XCTAssertEqual(request.threadID, "thread-1")
        XCTAssertEqual(request.turnID, "turn-1")
        XCTAssertEqual(request.itemID, "item-1")

        guard case .commandApproval(let approval) = request.kind else {
            return XCTFail("Expected command approval request")
        }

        XCTAssertEqual(approval.command, "git status")
        XCTAssertEqual(approval.cwd, "/tmp/repo")
        XCTAssertEqual(approval.reason, "Needs to inspect the working tree.")
        XCTAssertEqual(approval.actionSummaries.first?.title, "Git status")
    }

    func testInteractionRequestParsesLegacyPatchApproval() throws {
        let params = try TestJSONHelpers.makeJSONObject([
            "conversationId": "thread-legacy",
            "callId": "call-1",
            "reason": "Agent wants to edit files.",
            "fileChanges": [
                "Sources/App.swift": ["type": "update", "unified_diff": "@@ ..."],
                "README.md": ["type": "add", "content": "hello"]
            ]
        ])

        let request = try XCTUnwrap(
            CodexAppServerAdapter.interactionRequest(
                id: .int(2),
                method: "applyPatchApproval",
                params: params
            )
        )

        guard case .fileChangeApproval(let approval) = request.kind else {
            return XCTFail("Expected file change approval request")
        }

        XCTAssertEqual(approval.fileChanges.count, 2)
        XCTAssertEqual(approval.fileChanges.first?.path, "README.md")
        XCTAssertEqual(approval.fileChanges.last?.path, "Sources/App.swift")
    }

    func testInteractionRequestParsesToolRequestUserInput() throws {
        let params = try TestJSONHelpers.makeJSONObject([
            "threadId": "thread-2",
            "turnId": "turn-2",
            "itemId": "item-2",
            "questions": [
                [
                    "header": "Sandbox",
                    "id": "sandbox_mode",
                    "question": "Which sandbox should I use?",
                    "options": [
                        ["label": "Workspace Write", "description": "Recommended"],
                        ["label": "Read Only", "description": "Safer"],
                    ]
                ],
                [
                    "header": "Path",
                    "id": "repo_path",
                    "question": "What repo should I work in?",
                    "isOther": true,
                    "isSecret": false
                ]
            ]
        ])

        let request = try XCTUnwrap(
            CodexAppServerAdapter.interactionRequest(
                id: .int(3),
                method: "item/tool/requestUserInput",
                params: params
            )
        )

        guard case .userInput(let userInput) = request.kind else {
            return XCTFail("Expected request-user-input payload")
        }

        XCTAssertEqual(userInput.questions.count, 2)
        XCTAssertEqual(userInput.questions[0].options.first?.label, "Workspace Write")
        XCTAssertTrue(userInput.questions[1].isOtherAllowed)
    }
}
