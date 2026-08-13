import XCTest
@testable import Jin

final class ChatGenerationControlsPersistenceSupportTests: XCTestCase {
    func testMergedForPersistKeepsLiveComposerControlsAndStoredClaudeSession() {
        var live = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high),
            webSearch: WebSearchControls(enabled: true),
            mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: ["github"])
        )
        live.claudeManagedSessionID = "live-session"
        live.claudeManagedSessionModelID = "live-model"
        live.claudeManagedPendingCustomToolResults = []

        var stored = GenerationControls(
            reasoning: ReasoningControls(enabled: false, effort: .low)
        )
        stored.claudeManagedSessionID = "stored-session"
        stored.claudeManagedSessionModelID = "stored-model"
        stored.claudeManagedPendingCustomToolResults = [
            ClaudeManagedAgentPendingToolResult(
                eventID: "evt-1",
                toolCallID: "tool-1",
                toolName: "lookup",
                content: "done",
                isError: false,
                sessionThreadID: nil
            )
        ]

        let merged = ChatGenerationControlsPersistenceSupport.mergedForPersist(
            live: live,
            stored: stored
        )

        XCTAssertEqual(merged.reasoning?.effort, .high)
        XCTAssertEqual(merged.webSearch?.enabled, true)
        XCTAssertEqual(merged.mcpTools?.enabledServerIDs, ["github"])
        XCTAssertEqual(merged.claudeManagedSessionID, "stored-session")
        XCTAssertEqual(merged.claudeManagedSessionModelID, "stored-model")
        XCTAssertEqual(merged.claudeManagedPendingCustomToolResults.count, 1)
        XCTAssertEqual(merged.claudeManagedPendingCustomToolResults.first?.toolCallID, "tool-1")
    }

    func testMergedForPersistClearsPendingToolResultsWhenStoredHasNone() {
        var live = GenerationControls()
        live.claudeManagedPendingCustomToolResults = [
            ClaudeManagedAgentPendingToolResult(
                eventID: "evt-stale",
                toolCallID: "stale",
                toolName: "lookup",
                content: "old",
                isError: false,
                sessionThreadID: nil
            )
        ]

        let merged = ChatGenerationControlsPersistenceSupport.mergedForPersist(
            live: live,
            stored: GenerationControls()
        )

        XCTAssertTrue(merged.claudeManagedPendingCustomToolResults.isEmpty)
    }

    func testEncodedPayloadIfChangedSkipsUnchangedBytes() throws {
        let controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .medium)
        )
        let encoded = try XCTUnwrap(
            ChatGenerationControlsPersistenceSupport.encodedPayloadIfChanged(
                merged: controls,
                currentData: Data()
            )
        )

        XCTAssertNil(
            ChatGenerationControlsPersistenceSupport.encodedPayloadIfChanged(
                merged: controls,
                currentData: encoded
            )
        )
    }

    func testEncodedPayloadIfChangedReturnsBytesWhenReasoningChanges() throws {
        let current = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .low)
        )
        let next = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high)
        )
        let currentData = try JSONEncoder().encode(current)

        let encoded = ChatGenerationControlsPersistenceSupport.encodedPayloadIfChanged(
            merged: next,
            currentData: currentData
        )

        XCTAssertNotNil(encoded)
        let decoded = try JSONDecoder().decode(GenerationControls.self, from: try XCTUnwrap(encoded))
        XCTAssertEqual(decoded.reasoning?.effort, .high)
    }

    func testGoogleMapsLocationBiasUsesCoordinatesOnly() {
        XCTAssertNil(
            ChatGenerationControlsPersistenceSupport.googleMapsLocationBias(
                from: GenerationControls(googleMaps: GoogleMapsControls(enabled: true))
            )
        )

        let bias = ChatGenerationControlsPersistenceSupport.googleMapsLocationBias(
            from: GenerationControls(
                googleMaps: GoogleMapsControls(enabled: true, latitude: 37.8, longitude: -122.4)
            )
        )
        XCTAssertEqual(bias?.latitude, 37.8)
        XCTAssertEqual(bias?.longitude, -122.4)
    }
}
