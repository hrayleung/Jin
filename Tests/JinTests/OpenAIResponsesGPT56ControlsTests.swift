import XCTest
@testable import Jin

final class OpenAIResponsesGPT56ControlsTests: XCTestCase {
    func testApplyReasoningConfigIncludesProModeAndMaxEffort() throws {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .max,
                mode: .pro,
                context: .allTurns
            ),
            textVerbosity: .low
        )

        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: .openai,
            modelID: "gpt-5.6-sol",
            reasoningEnabled: true,
            reasoningEffort: .max
        )

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "max")
        XCTAssertEqual(reasoning["mode"] as? String, "pro")
        XCTAssertEqual(reasoning["context"] as? String, "all_turns")

        let text = try XCTUnwrap(body["text"] as? [String: Any])
        XCTAssertEqual(text["verbosity"] as? String, "low")
    }

    func testProModeNotEmittedForUnsupportedModels() throws {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high, mode: .pro)
        )

        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: .openai,
            modelID: "gpt-5.5",
            reasoningEnabled: true,
            reasoningEffort: .high
        )

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "high")
        XCTAssertNil(reasoning["mode"])
    }

    func testReasoningOffOmitsPersistedSummaryModeAndContext() throws {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: false,
                effort: .high,
                summary: .auto,
                mode: .pro,
                context: .allTurns
            ),
            textVerbosity: .medium
        )

        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: .openai,
            modelID: "gpt-5.6-sol",
            reasoningEnabled: false,
            reasoningEffort: .high
        )

        XCTAssertNil(body["reasoning"])
        // Verbosity remains independent of reasoning off.
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        XCTAssertEqual(text["verbosity"] as? String, "medium")
    }

    func testReasoningContextNotEmittedForUnsupportedModels() throws {
        var body: [String: Any] = [:]
        let controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .high,
                context: .currentTurn
            )
        )

        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: .openai,
            modelID: "gpt-5.5",
            reasoningEnabled: true,
            reasoningEffort: .high
        )

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "high")
        XCTAssertNil(reasoning["context"])
    }

    func testEnsureOpenAIReasoningActiveSeedsDefaultEffortForProMode() {
        var reasoning = ReasoningControls(enabled: false, effort: nil, mode: .pro)
        ChatReasoningSupport.ensureOpenAIReasoningActive(
            &reasoning,
            defaultEffort: .medium,
            supportsReasoningSummaryControl: true
        )
        XCTAssertTrue(reasoning.enabled)
        XCTAssertEqual(reasoning.effort, .medium)
        XCTAssertEqual(reasoning.summary, .auto)

        // Existing non-none effort is preserved.
        var withHigh = ReasoningControls(enabled: true, effort: .high, mode: .pro)
        ChatReasoningSupport.ensureOpenAIReasoningActive(
            &withHigh,
            defaultEffort: .medium,
            supportsReasoningSummaryControl: true
        )
        XCTAssertEqual(withHigh.effort, .high)
    }

    func testProModeWithSeededEffortEmitsReasoningMode() throws {
        var reasoning = ReasoningControls(enabled: false, effort: nil, mode: nil)
        reasoning.mode = .pro
        ChatReasoningSupport.ensureOpenAIReasoningActive(
            &reasoning,
            defaultEffort: .medium,
            supportsReasoningSummaryControl: true
        )

        let effort = (reasoning.enabled == true) ? reasoning.effort : nil
        let reasoningEnabled = (effort ?? .none) != .none
        XCTAssertTrue(reasoningEnabled)

        var body: [String: Any] = [:]
        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: GenerationControls(reasoning: reasoning),
            providerType: .openai,
            modelID: "gpt-5.6-sol",
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: effort
        )

        let payload = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(payload["mode"] as? String, "pro")
        XCTAssertEqual(payload["effort"] as? String, "medium")
    }
}
