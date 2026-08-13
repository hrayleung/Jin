import XCTest
@testable import Jin

final class ModalEndpointSupportTests: XCTestCase {

    func testSharedRegionsMatchCanonicalAndHostOnlyURLs() {
        XCTAssertEqual(
            ModalSharedRegion.matching(baseURL: "https://inference.us-west.modal.direct/v1"),
            .usWest
        )
        XCTAssertEqual(
            ModalSharedRegion.matching(baseURL: "https://inference.eu-west.modal.direct"),
            .euWest
        )
        XCTAssertEqual(
            ModalSharedRegion.matching(baseURL: "https://inference.us-east.modal.direct/v1/"),
            .usEast
        )
        XCTAssertNil(ModalSharedRegion.matching(baseURL: "https://workspace--app-server.us-west.modal.direct"))
        XCTAssertNil(ModalSharedRegion.matching(baseURL: "https://inference.mars.modal.direct/v1"))
    }

    func testAutoEndpointHostParsesURLHostAndBareHostname() {
        XCTAssertEqual(
            ModalEndpointSupport.autoEndpointHost(
                from: "https://workspace--qwen-server.us-west.modal.direct/v1"
            ),
            "workspace--qwen-server.us-west.modal.direct"
        )
        XCTAssertEqual(
            ModalEndpointSupport.autoEndpointHost(
                from: "  workspace--qwen-server.us-west.modal.direct  "
            ),
            "workspace--qwen-server.us-west.modal.direct"
        )
        XCTAssertEqual(
            ModalEndpointSupport.autoEndpointHost(
                from: "HTTPS://Workspace--Qwen-Server.US-WEST.modal.direct/"
            ),
            "workspace--qwen-server.us-west.modal.direct"
        )
    }

    func testAutoEndpointHostRejectsSharedAPIAndNonModalValues() {
        XCTAssertNil(
            ModalEndpointSupport.autoEndpointHost(from: "https://inference.us-west.modal.direct/v1")
        )
        XCTAssertNil(ModalEndpointSupport.autoEndpointHost(from: "Qwen/Qwen3.8-2.4T-A95B"))
        XCTAssertNil(ModalEndpointSupport.autoEndpointHost(from: "https://example.com"))
        XCTAssertNil(ModalEndpointSupport.autoEndpointHost(from: ".modal.direct"))
        XCTAssertNil(ModalEndpointSupport.autoEndpointHost(from: ""))
    }

    func testNormalizedModelIDKeepsHFReposAndCollapsesEndpointURLs() {
        XCTAssertEqual(
            ModalEndpointSupport.normalizedModelID(from: "Qwen/Qwen3.8-2.4T-A95B"),
            "Qwen/Qwen3.8-2.4T-A95B"
        )
        XCTAssertEqual(
            ModalEndpointSupport.normalizedModelID(
                from: "https://acme--kimi-server.eu-west.modal.direct/v1"
            ),
            "acme--kimi-server.eu-west.modal.direct"
        )
    }

    func testDisplayNameUsesFirstDNSLabel() {
        XCTAssertEqual(
            ModalEndpointSupport.displayName(forModelID: "acme--kimi-server.us-west.modal.direct"),
            "acme--kimi-server"
        )
        XCTAssertNil(ModalEndpointSupport.displayName(forModelID: "moonshotai/Kimi-K3"))
        XCTAssertNil(ModalEndpointSupport.displayName(forModelID: "inference.us-west.modal.direct"))
    }

    func testModelInfoFromPastedEndpointUsesHostnameIDAndEndpointMetadata() throws {
        let info = try XCTUnwrap(
            ModalEndpointSupport.modelInfo(
                fromPasted: "https://acme--qwen-server.us-west.modal.direct",
                nickname: "Qwen coding"
            )
        )
        XCTAssertEqual(info.id, "acme--qwen-server.us-west.modal.direct")
        XCTAssertEqual(info.name, "Qwen coding")
        XCTAssertEqual(
            info.catalogMetadata?.requestBaseURL,
            "https://acme--qwen-server.us-west.modal.direct/v1"
        )
        XCTAssertNil(info.catalogMetadata?.upstreamModelID)
        XCTAssertTrue(ModalEndpointSupport.isAutoEndpointModelID(info.id))
    }

    func testModelInfoUsesCatalogCapabilitiesWhenUpstreamIDIsKnown() throws {
        let info = try XCTUnwrap(
            ModalEndpointSupport.modelInfo(
                fromPasted: "https://acme--qwen-server.us-west.modal.direct",
                nickname: nil,
                upstreamModelID: "Qwen/Qwen3.8-2.4T-A95B"
            )
        )
        XCTAssertEqual(info.id, "Qwen/Qwen3.8-2.4T-A95B")
        XCTAssertEqual(info.name, "Qwen3.8 Max")
        XCTAssertEqual(info.catalogMetadata?.upstreamModelID, "Qwen/Qwen3.8-2.4T-A95B")
        XCTAssertEqual(
            info.catalogMetadata?.requestBaseURL,
            "https://acme--qwen-server.us-west.modal.direct/v1"
        )
        XCTAssertEqual(info.contextWindow, 1_000_000)
        XCTAssertTrue(info.capabilities.contains(.reasoning))
        XCTAssertFalse(info.capabilities.contains(.vision))
        XCTAssertFalse(ModalEndpointSupport.isAutoEndpointModelID(info.id))
        XCTAssertTrue(ModalEndpointSupport.isAutoEndpointModel(info))
        XCTAssertEqual(
            ModalEndpointSupport.userFacingModelID(for: info),
            "Qwen/Qwen3.8-2.4T-A95B"
        )
        XCTAssertEqual(
            ModalEndpointSupport.catalogModelID(for: info),
            "Qwen/Qwen3.8-2.4T-A95B"
        )
    }

    func testUserFacingModelIDHidesEndpointHostnames() throws {
        let unnamed = try XCTUnwrap(
            ModalEndpointSupport.modelInfo(
                fromPasted: "https://acme--qwen-server.us-west.modal.direct",
                nickname: "Qwen coding"
            )
        )
        XCTAssertNil(ModalEndpointSupport.userFacingModelID(for: unnamed))
        XCTAssertEqual(ModalEndpointSupport.catalogModelID(for: unnamed), unnamed.id)

        let shared = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .modal)
        XCTAssertEqual(ModalEndpointSupport.userFacingModelID(for: shared), "moonshotai/Kimi-K3")
    }

    func testRequestRouteSendsDirectlyToTheEndpointWithTheRepoID() {
        let model = ModalEndpointSupport.modelInfo(
            fromPasted: "https://acme--qwen-server.us-west.modal.direct",
            nickname: nil,
            upstreamModelID: "Qwen/Qwen3.8-2.4T-A95B"
        )
        let byRepoID = ModalEndpointSupport.requestRoute(
            modelID: "Qwen/Qwen3.8-2.4T-A95B",
            configured: model,
            providerBaseURL: "https://inference.us-west.modal.direct/v1"
        )
        XCTAssertEqual(byRepoID.baseURL, "https://acme--qwen-server.us-west.modal.direct/v1")
        XCTAssertEqual(byRepoID.wireModelID, "Qwen/Qwen3.8-2.4T-A95B")

        let byLegacyHost = ModalEndpointSupport.requestRoute(
            modelID: "acme--qwen-server.us-west.modal.direct",
            configured: model,
            providerBaseURL: "https://inference.us-west.modal.direct/v1"
        )
        XCTAssertEqual(byLegacyHost.baseURL, "https://acme--qwen-server.us-west.modal.direct/v1")
        XCTAssertEqual(byLegacyHost.wireModelID, "Qwen/Qwen3.8-2.4T-A95B")
    }

    func testRequestRouteKeepsSharedCatalogModelsOnTheProviderHost() {
        let route = ModalEndpointSupport.requestRoute(
            modelID: "Qwen/Qwen3.8-2.4T-A95B",
            configured: nil,
            providerBaseURL: "https://inference.us-west.modal.direct/v1"
        )
        XCTAssertEqual(route.baseURL, "https://inference.us-west.modal.direct/v1")
        XCTAssertEqual(route.wireModelID, "Qwen/Qwen3.8-2.4T-A95B")
    }

    func testRequestRouteKeepsHostnameOnlyRowsOnTheSharedAPI() throws {
        let sharedBase = "https://inference.us-west.modal.direct/v1"
        let fetchedHost = "my-endpoint.us-west.modal.direct"
        let fetched = ModalEndpointSupport.applyEndpointMetadataIfNeeded(
            to: ModelCatalog.modelInfo(for: fetchedHost, provider: .modal, name: "my-endpoint")
        )
        XCTAssertNil(fetched.catalogMetadata?.requestBaseURL)

        let fetchedRoute = ModalEndpointSupport.requestRoute(
            modelID: fetchedHost,
            configured: fetched,
            providerBaseURL: sharedBase
        )
        XCTAssertEqual(fetchedRoute.baseURL, sharedBase)
        XCTAssertEqual(fetchedRoute.wireModelID, fetchedHost)

        let pastedWithoutLookup = try XCTUnwrap(
            ModalEndpointSupport.modelInfo(
                fromPasted: "https://acme--qwen-server.us-west.modal.direct",
                nickname: "Qwen coding"
            )
        )
        XCTAssertEqual(
            pastedWithoutLookup.catalogMetadata?.requestBaseURL,
            "https://acme--qwen-server.us-west.modal.direct/v1"
        )
        let pastedRoute = ModalEndpointSupport.requestRoute(
            modelID: pastedWithoutLookup.id,
            configured: pastedWithoutLookup,
            providerBaseURL: sharedBase
        )
        XCTAssertEqual(pastedRoute.baseURL, sharedBase)
        XCTAssertEqual(pastedRoute.wireModelID, "acme--qwen-server.us-west.modal.direct")
    }

    func testAddModelSheetNormalizesModalEndpointPaste() {
        XCTAssertEqual(
            AddModelSheetSupport.normalizedModelID(
                "https://acme--app-server.us-east.modal.direct/v1",
                providerType: .modal
            ),
            "acme--app-server.us-east.modal.direct"
        )
        XCTAssertEqual(
            AddModelSheetSupport.resolvedModelName(
                nickname: "",
                modelID: "https://acme--app-server.us-east.modal.direct",
                providerType: .modal
            ),
            "acme--app-server"
        )
        XCTAssertEqual(
            AddModelSheetSupport.normalizedModelID(
                "https://acme--app-server.us-east.modal.direct/v1",
                providerType: .openai
            ),
            "https://acme--app-server.us-east.modal.direct/v1"
        )
    }

    func testPromoteIdentitiesRewritesHostnameIDToTheRepoID() throws {
        let leftover = ModelInfo(
            id: "jimmychou985--ep-qwen3-8-2-4t-a95b-server.us-west.modal.direct",
            name: "Qwen3.8 Max",
            capabilities: [.streaming],
            contextWindow: 128_000,
            catalogMetadata: ModelCatalogMetadata(
                requestBaseURL: "https://jimmychou985--ep-qwen3-8-2-4t-a95b-server.us-west.modal.direct/v1",
                upstreamModelID: "Qwen/Qwen3.8-2.4T-A95B"
            )
        )
        let promoted = ModalEndpointSupport.promoteIdentities(in: [leftover])
        XCTAssertEqual(promoted.map(\.id), ["Qwen/Qwen3.8-2.4T-A95B"])
        XCTAssertEqual(
            ModalEndpointSupport.userFacingModelID(for: promoted[0]),
            "Qwen/Qwen3.8-2.4T-A95B"
        )
        XCTAssertTrue(ModalEndpointSupport.isAutoEndpointModel(promoted[0]))
        XCTAssertEqual(
            ModalEndpointSupport.configuredModel(
                in: promoted,
                matching: leftover.id
            )?.id,
            "Qwen/Qwen3.8-2.4T-A95B"
        )
    }

    func testPromoteIdentitiesKeepsASecondEndpointWhenRepoIDsCollide() {
        let west = ModelInfo(
            id: "acme--qwen-west.us-west.modal.direct",
            name: "Qwen west",
            capabilities: [],
            contextWindow: 128_000,
            catalogMetadata: ModelCatalogMetadata(
                requestBaseURL: "https://acme--qwen-west.us-west.modal.direct/v1",
                upstreamModelID: "Qwen/Qwen3.8-2.4T-A95B"
            )
        )
        let east = ModelInfo(
            id: "acme--qwen-east.us-east.modal.direct",
            name: "Qwen east",
            capabilities: [],
            contextWindow: 128_000,
            catalogMetadata: ModelCatalogMetadata(
                requestBaseURL: "https://acme--qwen-east.us-east.modal.direct/v1",
                upstreamModelID: "Qwen/Qwen3.8-2.4T-A95B"
            )
        )
        let promoted = ModalEndpointSupport.promoteIdentities(in: [west, east])
        XCTAssertEqual(promoted[0].id, "Qwen/Qwen3.8-2.4T-A95B")
        XCTAssertEqual(promoted[1].id, "acme--qwen-east.us-east.modal.direct")
        XCTAssertEqual(
            ModalEndpointSupport.userFacingModelID(for: promoted[1]),
            "Qwen/Qwen3.8-2.4T-A95B"
        )
    }

    func testModalProviderHelpCopyStaysQuiet() {
        XCTAssertNil(ProviderFormSupport.providerDetailsText(for: .modal))
    }
}
