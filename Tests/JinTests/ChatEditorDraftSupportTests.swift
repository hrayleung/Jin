import XCTest
@testable import Jin

final class ChatEditorDraftSupportTests: XCTestCase {
    func testAnthropicThinkingDraftValidationUsesCurrentMaxTokensFallbackWhenDraftIsEmpty() {
        XCTAssertTrue(
            ChatEditorDraftSupport.isThinkingBudgetDraftValid(
                anthropicUsesAdaptiveThinking: true,
                providerType: .anthropic,
                modelID: "claude-opus-4-7",
                thinkingBudgetDraft: "",
                maxTokensDraft: "",
                currentMaxTokens: 64_000
            )
        )
        XCTAssertNil(
            ChatEditorDraftSupport.thinkingBudgetValidationWarning(
                providerType: .anthropic,
                anthropicUsesAdaptiveThinking: true,
                modelID: "claude-opus-4-7",
                thinkingBudgetDraft: "",
                maxTokensDraft: "",
                currentMaxTokens: 64_000
            )
        )
    }

    func testAnthropicThinkingDraftValidationStillRejectsNonNumericMaxTokens() {
        XCTAssertFalse(
            ChatEditorDraftSupport.isThinkingBudgetDraftValid(
                anthropicUsesAdaptiveThinking: true,
                providerType: .anthropic,
                modelID: "claude-opus-4-7",
                thinkingBudgetDraft: "",
                maxTokensDraft: "abc",
                currentMaxTokens: 64_000
            )
        )
        XCTAssertEqual(
            ChatEditorDraftSupport.thinkingBudgetValidationWarning(
                providerType: .anthropic,
                anthropicUsesAdaptiveThinking: true,
                modelID: "claude-opus-4-7",
                thinkingBudgetDraft: "",
                maxTokensDraft: "abc",
                currentMaxTokens: 64_000
            ),
            "Enter a valid positive max output token value."
        )
    }

    func testApplyClaudeManagedAgentSessionSettingsDraftRequiresBothAgentAndEnvironment() {
        let result = ChatEditorDraftSupport.applyClaudeManagedAgentSessionSettingsDraft(
            agentIDDraft: "agent_123",
            environmentIDDraft: "",
            agentDisplayNameDraft: "Build Agent",
            environmentDisplayNameDraft: "",
            controls: GenerationControls()
        )

        switch result {
        case .success:
            XCTFail("Expected validation failure when only one managed agent identifier is provided.")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, "Enter both Agent ID and Environment ID, or leave both blank.")
        }
    }

    func testApplyClaudeManagedAgentSessionSettingsDraftNormalizesConfiguredValues() {
        let result = ChatEditorDraftSupport.applyClaudeManagedAgentSessionSettingsDraft(
            agentIDDraft: " agent_123 ",
            environmentIDDraft: " env_456 ",
            agentDisplayNameDraft: " Build Agent ",
            environmentDisplayNameDraft: " macOS Workspace ",
            controls: GenerationControls()
        )

        switch result {
        case .success(let controls):
            XCTAssertEqual(controls.claudeManagedAgentID, "agent_123")
            XCTAssertEqual(controls.claudeManagedEnvironmentID, "env_456")
            XCTAssertEqual(controls.claudeManagedAgentDisplayName, "Build Agent")
            XCTAssertEqual(controls.claudeManagedEnvironmentDisplayName, "macOS Workspace")
        case .failure(let error):
            XCTFail("Unexpected validation error: \(error.localizedDescription)")
        }
    }
}
