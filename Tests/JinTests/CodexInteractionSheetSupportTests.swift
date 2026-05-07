import XCTest
@testable import Jin

final class CodexInteractionSheetSupportTests: XCTestCase {
    func testInitialSelectedOptionsUsesFirstOptionPerQuestion() {
        let input = CodexUserInputRequest(questions: [
            question(id: "mode", options: [
                CodexUserInputOption(label: "Recommended", detail: "Use this"),
                CodexUserInputOption(label: "Other", detail: "Fallback")
            ]),
            question(id: "path", options: [])
        ])

        XCTAssertEqual(
            CodexInteractionSheetSupport.initialSelectedOptions(for: input),
            ["mode": "Recommended"]
        )
    }

    func testRequestDescriptionMatchesInteractionKind() {
        XCTAssertEqual(
            CodexInteractionSheetSupport.requestDescription(
                for: .commandApproval(CodexCommandApprovalRequest(
                    command: "git status",
                    cwd: nil,
                    reason: nil,
                    actionSummaries: []
                ))
            ),
            "Codex paused because the current approval policy requires explicit consent for this command."
        )
        XCTAssertEqual(
            CodexInteractionSheetSupport.requestDescription(
                for: .fileChangeApproval(CodexFileChangeApprovalRequest(
                    reason: nil,
                    grantRoot: nil,
                    fileChanges: []
                ))
            ),
            "Codex paused before writing files outside the current allowance."
        )
        XCTAssertEqual(
            CodexInteractionSheetSupport.requestDescription(
                for: .userInput(CodexUserInputRequest(questions: []))
            ),
            "Codex needs a small bit of guidance before it can continue the turn."
        )
    }

    func testCancelResponseMatchesInteractionKind() {
        if case .approval(.cancel) = CodexInteractionSheetSupport.cancelResponse(
            for: .commandApproval(CodexCommandApprovalRequest(
                command: nil,
                cwd: nil,
                reason: nil,
                actionSummaries: []
            ))
        ) {
            // Expected.
        } else {
            XCTFail("Expected approval cancellation")
        }

        if case .cancelled(let message) = CodexInteractionSheetSupport.cancelResponse(
            for: .userInput(CodexUserInputRequest(questions: []))
        ) {
            XCTAssertEqual(message, "User cancelled the Codex interaction.")
        } else {
            XCTFail("Expected user input cancellation")
        }
    }

    func testAnswersPreferFreeTextThenSelectedOptionsAndTrimWhitespace() {
        let input = CodexUserInputRequest(questions: [
            question(id: "mode"),
            question(id: "path")
        ])

        XCTAssertEqual(
            CodexInteractionSheetSupport.answers(
                for: input,
                textAnswers: ["mode": "  custom  "],
                selectedOptions: ["mode": "Recommended", "path": "  /repo  "]
            ),
            [
                "mode": ["custom"],
                "path": ["/repo"]
            ]
        )
    }

    func testAnswersRequireEveryQuestion() {
        let input = CodexUserInputRequest(questions: [
            question(id: "mode"),
            question(id: "path")
        ])

        XCTAssertNil(
            CodexInteractionSheetSupport.answers(
                for: input,
                textAnswers: ["mode": "Recommended"],
                selectedOptions: [:]
            )
        )
    }

    private func question(
        id: String,
        options: [CodexUserInputOption] = []
    ) -> CodexUserInputQuestion {
        CodexUserInputQuestion(
            id: id,
            header: id,
            prompt: "Prompt",
            isOtherAllowed: false,
            isSecret: false,
            options: options
        )
    }
}
