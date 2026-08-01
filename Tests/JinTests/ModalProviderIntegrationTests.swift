import XCTest
@testable import Jin

final class ModalProviderIntegrationTests: XCTestCase {

    func testProviderTypeDefaults() {
        XCTAssertEqual(ProviderType.modal.displayName, "Modal")
        XCTAssertEqual(ProviderType.modal.defaultBaseURL, "https://inference.us-west.modal.direct/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .modal), "Modal")
        // Modal has no explicit cache controls — vLLM prefix caching is automatic.
        XCTAssertFalse(ProviderType.modal.supportsNativePromptCaching)
        XCTAssertFalse(ProviderType.modal.supportsNativePDFUpload)
    }

    func testSeededModelsMatchSharedAPICatalog() {
        let seeded = ModelCatalog.seededModels(for: .modal)
        let expectedIDs = [
            "moonshotai/Kimi-K3",
            "thinkingmachines/Inkling-NVFP4",
        ]
        XCTAssertEqual(seeded.map(\.id), expectedIDs)

        for id in expectedIDs {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .modal), id)
        }
    }

    func testKimiK3CatalogMetadata() {
        let info = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .modal)
        XCTAssertEqual(info.name, "Kimi K3")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 262_144)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertTrue(info.capabilities.contains(.promptCaching))
        XCTAssertEqual(info.reasoningConfig?.type, .effort)
        XCTAssertEqual(info.reasoningConfig?.defaultEffort, .max)

        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .modal, modelID: "moonshotai/Kimi-K3"),
            [.none, .low, .high, .max]
        )
        // The effort menu offers `max`, so the wire mapper has to allow it too.
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .modal, modelID: "moonshotai/Kimi-K3")
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.max, for: .modal, modelID: "moonshotai/Kimi-K3"),
            .max
        )
    }

    func testInklingUsesModalNVFP4IDAndFullEffortBand() {
        let info = ModelCatalog.modelInfo(for: "thinkingmachines/Inkling-NVFP4", provider: .modal)
        XCTAssertEqual(info.name, "Inkling")
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 262_144)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.audio))

        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .modal, modelID: "thinkingmachines/Inkling-NVFP4"),
            [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        )

        // Modal's slug differs from the `thinkingmachines/inkling` other providers
        // use; the bare slug must not resolve into Modal's catalog.
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "thinkingmachines/inkling", provider: .modal))
    }

    func testModalHasNoServerSideToolSurfaces() {
        for id in ["moonshotai/Kimi-K3", "thinkingmachines/Inkling-NVFP4"] {
            XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .modal, modelID: id), id)
            XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .modal, modelID: id), id)
            XCTAssertFalse(ModelCapabilityRegistry.supportsGoogleMaps(for: .modal, modelID: id), id)
        }
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .modal, modelID: "moonshotai/Kimi-K3"),
            .openAICompatible
        )
    }

    func testSeedConfigAndAdapterBaseURL() async {
        let config = DefaultProviderSeeds.modal
        XCTAssertEqual(config.id, "modal")
        XCTAssertEqual(config.type, .modal)
        XCTAssertEqual(config.baseURL, "https://inference.us-west.modal.direct/v1")
        XCTAssertEqual(config.models.map(\.id), ["moonshotai/Kimi-K3", "thinkingmachines/Inkling-NVFP4"])
        XCTAssertTrue(DefaultProviderSeeds.allProviders().contains(where: { $0.id == "modal" }))

        let adapter = ModalAdapter(providerConfig: config, apiKey: "wk-a.ws-b")
        let baseURL = await adapter.baseURL
        XCTAssertEqual(baseURL, "https://inference.us-west.modal.direct/v1")
    }

    func testAdapterAppendsV1ToARegionHostOrAutoEndpointURL() async {
        // A user pasting a bare host (either the shared gateway or their own Auto
        // Endpoint) should still reach /v1/chat/completions.
        for host in [
            "https://inference.eu-west.modal.direct",
            "https://my-endpoint.us-east.modal.direct/",
        ] {
            let config = ProviderConfig(id: "modal", name: "Modal", type: .modal, baseURL: host)
            let adapter = ModalAdapter(providerConfig: config, apiKey: "wk-a.ws-b")
            let baseURL = await adapter.baseURL
            XCTAssertTrue(baseURL.hasSuffix("/v1"), baseURL)
            XCTAssertFalse(baseURL.contains("//v1"), baseURL)
        }
    }

    func testProxyTokenParsing() {
        // Joined form is what Jin stores.
        XCTAssertEqual(ModalProxyToken.parse("wk-abc.ws-def"), ModalProxyToken(id: "wk-abc", secret: "ws-def"))
        XCTAssertEqual(ModalProxyToken.parse("  wk-abc.ws-def  ")?.combined, "wk-abc.ws-def")
        // The CLI prints the halves separately, so accept a pasted pair.
        XCTAssertEqual(ModalProxyToken.parse("wk-abc ws-def")?.combined, "wk-abc.ws-def")
        XCTAssertEqual(ModalProxyToken.parse("wk-abc\nws-def")?.combined, "wk-abc.ws-def")
        XCTAssertEqual(ModalProxyToken.parse("wk-abc:ws-def")?.combined, "wk-abc.ws-def")

        // Anything that isn't a recognizable pair must not be reshaped.
        XCTAssertNil(ModalProxyToken.parse("sk-not-a-modal-token"))
        XCTAssertNil(ModalProxyToken.parse("wk-abc"))
        XCTAssertNil(ModalProxyToken.parse("wk-abc.ws-"))
        XCTAssertNil(ModalProxyToken.parse("wk-abc ws-def ws-ghi"))
        XCTAssertEqual(ModalProxyToken.normalized("  sk-plain-key "), "sk-plain-key")
    }

    func testProxyTokenFieldRoundTrip() {
        // Half-typed credentials survive without becoming a broken `wk-abc.`.
        XCTAssertEqual(ModalProxyToken.storedValue(id: "wk-abc", secret: ""), "wk-abc")
        XCTAssertEqual(ModalProxyToken.storedValue(id: "", secret: "ws-def"), "ws-def")
        XCTAssertEqual(ModalProxyToken.storedValue(id: "wk-abc", secret: "ws-def"), "wk-abc.ws-def")

        let split = ModalProxyToken.fields(from: "wk-abc.ws-def")
        XCTAssertEqual(split.id, "wk-abc")
        XCTAssertEqual(split.secret, "ws-def")

        // An unrecognized value stays visible in the ID field rather than vanishing.
        let unknown = ModalProxyToken.fields(from: "sk-plain-key")
        XCTAssertEqual(unknown.id, "sk-plain-key")
        XCTAssertEqual(unknown.secret, "")
    }

    func testModalUsesTwoCredentialFieldsAndRequiresBothHalves() {
        XCTAssertEqual(ProviderFormSupport.credentialKind(for: .modal), .proxyTokenPair)

        // Half a token can't authenticate, so the actions stay disabled.
        XCTAssertTrue(ProviderFormSupport.isCredentialEmpty(providerType: .modal, apiKey: "wk-abc", serviceAccountJSON: ""))
        XCTAssertFalse(
            ProviderFormSupport.isCredentialEmpty(providerType: .modal, apiKey: "wk-abc.ws-def", serviceAccountJSON: "")
        )
        XCTAssertTrue(
            ProviderFormSupport.isTestConnectionDisabled(
                providerType: .modal, isTesting: false, apiKey: "wk-abc", serviceAccountJSON: ""
            )
        )
        XCTAssertFalse(
            ProviderFormSupport.isFetchModelsDisabled(
                isFetchingModels: false, providerType: .modal, apiKey: "wk-abc.ws-def", serviceAccountJSON: ""
            )
        )
    }

    func testAuthHeadersPreferTheProxyTokenPair() {
        let pair = ModalAdapter.authHeaders(for: "wk-abc.ws-def")
        XCTAssertEqual(pair.auth?.key, "Modal-Key")
        XCTAssertEqual(pair.auth?.value, "wk-abc")
        XCTAssertEqual(pair.additional["Modal-Secret"], "ws-def")

        // A non-pair credential falls back to the default bearer handling.
        let fallback = ModalAdapter.authHeaders(for: "sk-plain-key")
        XCTAssertNil(fallback.auth)
        XCTAssertTrue(fallback.additional.isEmpty)
    }

    func testHostnameModelIDsGetAFriendlyDisplayName() {
        // Auto Endpoints reached through the shared gateway are addressed by hostname.
        XCTAssertEqual(ModalAdapter.displayName(forModelID: "my-endpoint.us-west.modal.direct"), "my-endpoint")
        // Shared API models keep their repo ID.
        XCTAssertEqual(ModalAdapter.displayName(forModelID: "moonshotai/Kimi-K3"), "moonshotai/Kimi-K3")
    }

    func testPreferredModelIsKimiK3() {
        let models = ModelCatalog.seededModels(for: .modal)
        for preferredID in ChatModelSelectionSupport.preferredModalModelOrder {
            if models.contains(where: { $0.id == preferredID }) {
                XCTAssertEqual(preferredID, "moonshotai/Kimi-K3")
                return
            }
        }
        XCTFail("Expected Kimi K3 in preferred Modal order")
    }

    func testCreateAdapterReturnsModalAdapter() async throws {
        let config = DefaultProviderSeeds.modal
        var configured = config
        configured.apiKey = "wk-abc.ws-def"

        let adapter = try await ProviderManager().createAdapter(for: configured)
        XCTAssertTrue(adapter is ModalAdapter)
    }
}
