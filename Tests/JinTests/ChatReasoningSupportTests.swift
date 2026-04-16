import XCTest
@testable import Jin

final class ChatReasoningSupportTests: XCTestCase {
    func testApplyThinkingBudgetDraftPreservesAnthropicDisplaySelectionWhenMaxTokensDraftIsNil() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .xhigh,
                anthropicThinkingDisplay: .summarized
            )
        )

        let resolvedMaxTokensDraft = ChatReasoningSupport.applyThinkingBudgetDraft(
            controls: &controls,
            providerType: .anthropic,
            modelID: "claude-opus-4-7",
            anthropicUsesAdaptiveThinking: true,
            anthropicUsesEffortMode: true,
            anthropicThinkingDisplay: .omitted,
            budgetTokens: nil,
            maxTokens: nil,
            defaultEffort: .high,
            defaultBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.anthropicThinkingDisplay, .omitted)
        XCTAssertEqual(controls.maxTokens, 128_000)
        XCTAssertEqual(resolvedMaxTokensDraft, "128000")
    }
}
