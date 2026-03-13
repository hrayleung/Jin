import XCTest
@testable import Jin

final class ChatAuxiliaryControlSupportTests: XCTestCase {
    func testPrepareGoogleMapsEditorDraftPreservesSavedFields() {
        let current = GoogleMapsControls(
            enabled: true,
            enableWidget: true,
            latitude: 35.6764,
            longitude: 139.65,
            languageCode: "ja_JP"
        )

        let prepared = ChatAuxiliaryControlSupport.prepareGoogleMapsEditorDraft(
            current: current,
            isEnabled: false
        )

        XCTAssertEqual(prepared.draft.enabled, true)
        XCTAssertEqual(prepared.latitudeDraft, "35.6764")
        XCTAssertEqual(prepared.longitudeDraft, "139.65")
        XCTAssertEqual(prepared.languageCodeDraft, "ja_JP")
    }

    func testApplyGoogleMapsDraftRequiresBothCoordinates() {
        let result = ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: GoogleMapsControls(enabled: true),
            latitudeDraft: "35.0",
            longitudeDraft: "",
            languageCodeDraft: "",
            providerType: .gemini
        )

        switch result {
        case .success:
            XCTFail("Expected validation failure")
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, "Enter both latitude and longitude, or leave both empty.")
        }
    }

    func testApplyGoogleMapsDraftClearsUnsupportedLocaleOutsideVertex() throws {
        let result = try XCTUnwrap(
            try? ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
                draft: GoogleMapsControls(enabled: true, languageCode: "ja_JP"),
                latitudeDraft: "",
                longitudeDraft: "",
                languageCodeDraft: "ja_JP",
                providerType: .gemini
            ).get()
        )

        XCTAssertTrue(result.enabled)
        XCTAssertNil(result.languageCode)
    }

    func testApplyGoogleMapsDraftKeepsVertexLocaleAndNormalizesEmptyState() throws {
        let configured = try XCTUnwrap(
            try? ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
                draft: GoogleMapsControls(enabled: true),
                latitudeDraft: "34.050481",
                longitudeDraft: "-118.248526",
                languageCodeDraft: "en_US",
                providerType: .vertexai
            ).get()
        )

        XCTAssertEqual(configured.latitude, 34.050481)
        XCTAssertEqual(configured.longitude, -118.248526)
        XCTAssertEqual(configured.languageCode, "en_US")

        let empty = try? ChatAuxiliaryControlSupport.applyGoogleMapsDraft(
            draft: GoogleMapsControls(enabled: false),
            latitudeDraft: "",
            longitudeDraft: "",
            languageCodeDraft: "",
            providerType: .vertexai
        ).get()

        XCTAssertNil(empty)
    }

    func testResolvedMCPServerConfigsUsesPerMessageOverrideWhenConversationMCPDisabled() throws {
        var controls = GenerationControls()
        controls.mcpTools = MCPToolsControls(enabled: false, enabledServerIDs: nil)

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: true,
            servers: [makeServer(id: "alpha"), makeServer(id: "beta")],
            perMessageOverrideServerIDs: ["beta"]
        )

        XCTAssertEqual(configs.map(\.id), ["beta"])
    }

    func testResolvedMCPServerConfigsFiltersPerMessageOverrideToEligibleServers() throws {
        let controls = GenerationControls(mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: nil))
        let servers = [
            makeServer(id: "alpha"),
            makeServer(id: "beta", isEnabled: false),
            makeServer(id: "gamma", runToolsAutomatically: false)
        ]

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: true,
            servers: servers,
            perMessageOverrideServerIDs: ["alpha", "beta", "gamma", "missing"]
        )

        XCTAssertEqual(configs.map(\.id), ["alpha"])
    }

    func testResolvedMCPServerConfigsIgnoresPerMessageOverrideWhenMCPUnsupported() throws {
        let controls = GenerationControls(mcpTools: MCPToolsControls(enabled: true, enabledServerIDs: nil))

        let configs = try ChatAuxiliaryControlSupport.resolvedMCPServerConfigs(
            controls: controls,
            supportsMCPToolsControl: false,
            servers: [makeServer(id: "alpha")],
            perMessageOverrideServerIDs: ["alpha"]
        )

        XCTAssertTrue(configs.isEmpty)
    }

    private func makeServer(
        id: String,
        isEnabled: Bool = true,
        runToolsAutomatically: Bool = true
    ) -> MCPServerConfigEntity {
        let transport: MCPTransportConfig = .stdio(
            MCPStdioTransportConfig(command: "npx", args: ["-y", "mock-mcp-server"])
        )

        return MCPServerConfigEntity(
            id: id,
            name: id.capitalized,
            transportKindRaw: transport.kind.rawValue,
            transportData: try! JSONEncoder().encode(transport),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: true
        )
    }
}
