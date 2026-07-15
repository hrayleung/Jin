import XCTest
@testable import Jin

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
