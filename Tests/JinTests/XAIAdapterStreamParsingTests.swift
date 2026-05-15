import XCTest
@testable import Jin

final class XAIAdapterStreamParsingTests: XCTestCase {
    private func makeAdapter() -> XAIAdapter {
        let providerConfig = ProviderConfig(
            id: "x",
            name: "xAI",
            type: .xai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )
        return XAIAdapter(providerConfig: providerConfig, apiKey: "test-key")
    }

    func testOutputItemAddedEmitsXSearchActivity() async throws {
        let adapter = makeAdapter()
        let data = """
        {
            "output_index": 0,
            "sequence_number": 1,
            "item": {
                "id": "x_search_1",
                "type": "x_search_call",
                "status": "in_progress"
            }
        }
        """

        var functionCalls: [String: ResponsesAPIFunctionCallState] = [:]
        var codeState = OpenAICodeInterpreterState()
        let event = try await adapter.parseSSEEvent(
            type: "response.output_item.added",
            data: data,
            functionCallsByItemID: &functionCalls,
            codeInterpreterState: &codeState
        )

        guard case .searchActivity(let activity) = event else {
            return XCTFail("Expected .searchActivity, got \(String(describing: event))")
        }
        XCTAssertEqual(activity.id, "x_search_1")
        XCTAssertEqual(activity.type, "x_search_call")
        XCTAssertEqual(activity.status, .inProgress)
    }

    func testOutputItemAddedEmitsWebSearchActivity() async throws {
        let adapter = makeAdapter()
        let data = """
        {
            "output_index": 0,
            "sequence_number": 1,
            "item": {
                "id": "web_search_1",
                "type": "web_search_call",
                "status": "completed"
            }
        }
        """

        var functionCalls: [String: ResponsesAPIFunctionCallState] = [:]
        var codeState = OpenAICodeInterpreterState()
        let event = try await adapter.parseSSEEvent(
            type: "response.output_item.added",
            data: data,
            functionCallsByItemID: &functionCalls,
            codeInterpreterState: &codeState
        )

        guard case .searchActivity(let activity) = event else {
            return XCTFail("Expected .searchActivity, got \(String(describing: event))")
        }
        XCTAssertEqual(activity.id, "web_search_1")
        XCTAssertEqual(activity.type, "web_search_call")
        XCTAssertEqual(activity.status, .completed)
    }

    func testXSearchCallStatusEventEmitsCompletedActivity() async throws {
        let adapter = makeAdapter()
        let data = """
        {
            "output_index": 0,
            "item_id": "x_search_42",
            "sequence_number": 7
        }
        """

        var functionCalls: [String: ResponsesAPIFunctionCallState] = [:]
        var codeState = OpenAICodeInterpreterState()
        let event = try await adapter.parseSSEEvent(
            type: "response.x_search_call.completed",
            data: data,
            functionCallsByItemID: &functionCalls,
            codeInterpreterState: &codeState
        )

        guard case .searchActivity(let activity) = event else {
            return XCTFail("Expected .searchActivity, got \(String(describing: event))")
        }
        XCTAssertEqual(activity.id, "x_search_42")
        XCTAssertEqual(activity.type, "x_search_call")
        XCTAssertEqual(activity.status, .completed)
    }

    func testWebSearchCallStatusEventEmitsSearchingActivity() async throws {
        let adapter = makeAdapter()
        let data = """
        {
            "output_index": 0,
            "item_id": "web_search_99",
            "sequence_number": 3
        }
        """

        var functionCalls: [String: ResponsesAPIFunctionCallState] = [:]
        var codeState = OpenAICodeInterpreterState()
        let event = try await adapter.parseSSEEvent(
            type: "response.web_search_call.searching",
            data: data,
            functionCallsByItemID: &functionCalls,
            codeInterpreterState: &codeState
        )

        guard case .searchActivity(let activity) = event else {
            return XCTFail("Expected .searchActivity, got \(String(describing: event))")
        }
        XCTAssertEqual(activity.id, "web_search_99")
        XCTAssertEqual(activity.type, "web_search_call")
        XCTAssertEqual(activity.status, .searching)
    }

    func testOutputItemDoneEmitsXSearchActivity() async throws {
        let adapter = makeAdapter()
        let data = """
        {
            "output_index": 0,
            "sequence_number": 5,
            "item": {
                "id": "x_search_done",
                "type": "x_search_call",
                "status": "completed"
            }
        }
        """

        var functionCalls: [String: ResponsesAPIFunctionCallState] = [:]
        var codeState = OpenAICodeInterpreterState()
        let event = try await adapter.parseSSEEvent(
            type: "response.output_item.done",
            data: data,
            functionCallsByItemID: &functionCalls,
            codeInterpreterState: &codeState
        )

        guard case .searchActivity(let activity) = event else {
            return XCTFail("Expected .searchActivity, got \(String(describing: event))")
        }
        XCTAssertEqual(activity.id, "x_search_done")
        XCTAssertEqual(activity.type, "x_search_call")
        XCTAssertEqual(activity.status, .completed)
    }
}
