import XCTest
@testable import Jin

final class ChatEditorDraftSupportTests: XCTestCase {
    func testImageGenerationDraftValidationTrimsNumericFields() {
        XCTAssertTrue(
            ChatEditorDraftSupport.isImageGenerationDraftValid(
                seedDraft: " 42 ",
                compressionQualityDraft: " 100\n"
            )
        )
        XCTAssertTrue(
            ChatEditorDraftSupport.isImageGenerationDraftValid(
                seedDraft: " ",
                compressionQualityDraft: "\n"
            )
        )
        XCTAssertFalse(
            ChatEditorDraftSupport.isImageGenerationDraftValid(
                seedDraft: "seed",
                compressionQualityDraft: "90"
            )
        )
        XCTAssertFalse(
            ChatEditorDraftSupport.isImageGenerationDraftValid(
                seedDraft: "42",
                compressionQualityDraft: "101"
            )
        )
    }

    func testApplyImageGenerationDraftDropsVertexOnlyOptionsForNonVertexProviders() {
        let draft = ImageGenerationControls(
            aspectRatio: .ratio16x9,
            imageSize: .size4K,
            seed: 7,
            vertexPersonGeneration: .allowAdult,
            vertexOutputMIMEType: .jpeg,
            vertexCompressionQuality: 85
        )

        let result = ChatEditorDraftSupport.applyImageGenerationDraft(
            draft: draft,
            seedDraft: " 42 ",
            compressionQualityDraft: "90",
            supportsCurrentModelImageSizeControl: true,
            supportedCurrentModelImageSizes: [.size1K, .size2K],
            supportedCurrentModelImageAspectRatios: [.ratio1x1, .ratio16x9],
            providerType: .gemini
        )

        switch result {
        case .success(let controls):
            XCTAssertEqual(controls?.aspectRatio, .ratio16x9)
            XCTAssertNil(controls?.imageSize)
            XCTAssertEqual(controls?.seed, 42)
            XCTAssertNil(controls?.vertexPersonGeneration)
            XCTAssertNil(controls?.vertexOutputMIMEType)
            XCTAssertNil(controls?.vertexCompressionQuality)
        case .failure(let error):
            XCTFail("Unexpected validation error: \(error.localizedDescription)")
        }
    }

    func testThinkingBudgetDraftParsersTrimAndDropInvalidValues() {
        XCTAssertEqual(ChatEditorDraftSupport.thinkingBudgetDraftInt(from: " 4096\n"), 4096)
        XCTAssertNil(ChatEditorDraftSupport.thinkingBudgetDraftInt(from: "budget"))
        XCTAssertEqual(ChatEditorDraftSupport.maxTokensDraftInt(from: " 8192 "), 8192)
        XCTAssertNil(ChatEditorDraftSupport.maxTokensDraftInt(from: " "))
        XCTAssertNil(ChatEditorDraftSupport.maxTokensDraftInt(from: "0"))
    }

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
