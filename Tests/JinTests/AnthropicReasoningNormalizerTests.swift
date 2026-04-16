import XCTest
@testable import Jin

final class AnthropicReasoningNormalizerTests: XCTestCase {

    // MARK: - Opus 4.7 (adaptive thinking + xhigh/max effort)

    func testOpus47ClearsBudgetTokensAndDefaultsEffort() {
        var reasoning = ReasoningControls(enabled: true, budgetTokens: 8192)
        var maxTokens: Int? = nil

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-7"
        )

        XCTAssertNil(reasoning.budgetTokens, "budget_tokens must be nil on 4.7")
        XCTAssertEqual(reasoning.effort, .high, "effort should default to high")
        XCTAssertEqual(maxTokens, 128_000, "Opus 4.7 should resolve to model max when unset")
    }

    // MARK: - Opus 4.6 (adaptive thinking)

    func testOpus46ClearsBudgetTokensAndDefaultsEffort() {
        var reasoning = ReasoningControls(enabled: true, budgetTokens: 8192)
        var maxTokens: Int? = nil

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-6"
        )

        XCTAssertNil(reasoning.budgetTokens, "budget_tokens must be nil on 4.6")
        XCTAssertEqual(reasoning.effort, .high, "effort should default to high")
        XCTAssertEqual(maxTokens, 128_000, "Opus 4.6 should resolve to model max when unset")
    }

    func testOpus46VersionedModelIDResolvesMaxTokensToModelLimit() {
        var reasoning = ReasoningControls(enabled: true, budgetTokens: 4096)
        var maxTokens: Int? = nil

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-6-20260128"
        )

        XCTAssertEqual(maxTokens, 128_000, "Versioned Opus 4.6 IDs should resolve to 128k max output")
    }

    func testOpus46PreservesExplicitEffort() {
        var reasoning = ReasoningControls(enabled: true, effort: .low)
        var maxTokens: Int? = 4096

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-6"
        )

        XCTAssertEqual(reasoning.effort, .low, "explicit effort should be preserved")
        XCTAssertNil(reasoning.budgetTokens)
    }

    // MARK: - Opus 4.5 (effort + budget coexistence)

    func testOpus45PreservesEffortAndBudget() {
        var reasoning = ReasoningControls(enabled: true, effort: .low, budgetTokens: 8192)
        var maxTokens: Int? = 16000

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-5-20251101"
        )

        XCTAssertEqual(reasoning.effort, .low, "user's effort must be preserved")
        XCTAssertEqual(reasoning.budgetTokens, 8192, "user's budget must be preserved")
    }

    func testOpus45DefaultsEffortWhenNil() {
        var reasoning = ReasoningControls(enabled: true, budgetTokens: 4096)
        var maxTokens: Int? = 16000

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-5-20251101"
        )

        XCTAssertEqual(reasoning.effort, .high, "effort should default to high when nil")
        XCTAssertEqual(reasoning.budgetTokens, 4096)
    }

    func testOpus45DefaultsEffortWhenNone() {
        var reasoning = ReasoningControls(enabled: true, effort: ReasoningEffort.none, budgetTokens: 4096)
        var maxTokens: Int? = 16000

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-5-20251101"
        )

        XCTAssertEqual(reasoning.effort, .high, "effort .none should be replaced with default")
    }

    func testOpus45DefaultsBudgetWhenNil() {
        var reasoning = ReasoningControls(enabled: true, effort: .medium)
        var maxTokens: Int? = 16000
        let defaults = AnthropicReasoningNormalizer.Defaults(effort: .high, budgetTokens: 2048)

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-5-20251101",
            defaults: defaults
        )

        XCTAssertEqual(reasoning.effort, .medium, "explicit effort preserved")
        XCTAssertEqual(reasoning.budgetTokens, 2048, "budget should default from Defaults")
    }

    // MARK: - Opus 4.1

    func testOpus41PreservesEffortAndBudget() {
        var reasoning = ReasoningControls(enabled: true, effort: .medium, budgetTokens: 6000)
        var maxTokens: Int? = 8000

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-1-20250805"
        )

        XCTAssertEqual(reasoning.effort, .medium)
        XCTAssertEqual(reasoning.budgetTokens, 6000)
    }

    // MARK: - Older models (budget-only)

    func testSonnet45ClearsEffortAndDefaultsBudget() {
        var reasoning = ReasoningControls(enabled: true, effort: .high, budgetTokens: nil)
        var maxTokens: Int? = nil
        let defaults = AnthropicReasoningNormalizer.Defaults(effort: .high, budgetTokens: 1024)

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-sonnet-4-5-20250929",
            defaults: defaults
        )

        XCTAssertNil(reasoning.effort, "effort must be nil on budget-only models")
        XCTAssertEqual(reasoning.budgetTokens, 1024, "budget should default")
    }

    func testHaiku45ClearsEffort() {
        var reasoning = ReasoningControls(enabled: true, effort: .medium, budgetTokens: 2048)
        var maxTokens: Int? = 8000

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-haiku-4-5-20251001"
        )

        XCTAssertNil(reasoning.effort)
        XCTAssertEqual(reasoning.budgetTokens, 2048, "existing budget preserved")
    }

    // MARK: - Disabled reasoning

    func testDisabledReasoningClearsEverything() {
        var reasoning = ReasoningControls(enabled: false, effort: .high, budgetTokens: 4096)
        var maxTokens: Int? = 16000

        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-6"
        )

        XCTAssertNil(reasoning.effort)
        XCTAssertNil(reasoning.budgetTokens)
        XCTAssertNil(maxTokens)
    }

    // MARK: - Save-path regression: effort not clobbered on save

    func testOpus45SavePathPreservesUserEffort() {
        // Simulates the "user picks low effort in sheet, then clicks Save" flow.
        // The bug was: setAnthropicThinkingBudget cleared effort, then normalize defaulted to high.
        var reasoning = ReasoningControls(enabled: true, effort: .low, budgetTokens: 8192)
        var maxTokens: Int? = 16000

        // Step 1: user changes effort in the sheet → effort is already .low in controls
        // Step 2: user clicks Save → applyThinkingBudgetDraft sets budgetTokens
        reasoning.budgetTokens = 8192

        // Step 3: normalize runs
        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: "claude-opus-4-5-20251101"
        )

        // Effort must still be .low — not reset to .high
        XCTAssertEqual(reasoning.effort, .low, "User's effort selection must survive the save path")
        XCTAssertEqual(reasoning.budgetTokens, 8192)
    }
}
