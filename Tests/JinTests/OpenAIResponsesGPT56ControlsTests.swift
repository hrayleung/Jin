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
}

final class AnthropicRefusalStreamTests: XCTestCase {
    func testMessageDeltaRefusalSurfacesContentFilteredError() async throws {
        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )
        let adapter = AnthropicAdapter(providerConfig: providerConfig, apiKey: "test-key")

        var messageID: String? = "msg_1"
        var blockIndex: Int?
        var toolUse: AnthropicToolCallBuilder?
        var serverTool: AnthropicSearchActivityBuilder?
        var codeID: String?
        var code = ""
        var blockType: String?
        var thinkingSig: String?
        var usage = AnthropicUsageAccumulator()

        let line = """
        {"type":"message_delta","delta":{"stop_reason":"refusal","stop_sequence":null},"usage":{"input_tokens":10,"output_tokens":0}}
        """

        let event = try await adapter.parseJSONLine(
            line,
            currentMessageID: &messageID,
            currentBlockIndex: &blockIndex,
            currentToolUse: &toolUse,
            currentServerToolUse: &serverTool,
            currentCodeExecutionID: &codeID,
            currentCodeExecutionCode: &code,
            currentContentBlockType: &blockType,
            currentThinkingSignature: &thinkingSig,
            usageAccumulator: &usage
        )

        guard case .error(let error) = event else {
            return XCTFail("Expected error event, got \(String(describing: event))")
        }
        guard case .contentFiltered = error else {
            return XCTFail("Expected contentFiltered, got \(error)")
        }
    }
}
