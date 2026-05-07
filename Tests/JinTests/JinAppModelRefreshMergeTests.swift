import XCTest
import SwiftData
@testable import Jin

final class JinAppModelRefreshMergeTests: XCTestCase {
    @MainActor
    func testPostLaunchMaintenanceSeedsDefaultMCPServersForEmptyStore() throws {
        let suiteName = "JinAppModelRefreshMergeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-post-launch-maintenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let storeURL = temporaryDirectory.appendingPathComponent("store.sqlite", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let container = try PersistenceContainerFactory.makeContainer(storeURL: storeURL)
        let maintenance = AppPostLaunchMaintenance(defaults: defaults)

        maintenance.resetMCPServersForTransportV2IfNeeded(container: container)

        let context = ModelContext(container)
        let servers = try context.fetch(FetchDescriptor<MCPServerConfigEntity>())
            .sorted { $0.id < $1.id }

        XCTAssertEqual(servers.map(\.id), ["exa", "firecrawl"])
        XCTAssertEqual(defaults.integer(forKey: "mcpTransportSchemaVersion"), 2)

        let exa = try XCTUnwrap(servers.first { $0.id == "exa" })
        guard case .http(let exaTransport) = exa.transportConfig() else {
            return XCTFail("Expected Exa to use HTTP transport")
        }
        XCTAssertEqual(exaTransport.endpoint.absoluteString, "https://mcp.exa.ai/mcp")
        XCTAssertEqual(exaTransport.additionalHeaders, [MCPHeader(name: "X-Client", value: "jin")])

        let firecrawl = try XCTUnwrap(servers.first { $0.id == "firecrawl" })
        guard case .stdio(let firecrawlTransport) = firecrawl.transportConfig() else {
            return XCTFail("Expected Firecrawl to use stdio transport")
        }
        XCTAssertEqual(firecrawlTransport.command, "npx")
        XCTAssertEqual(firecrawlTransport.args, ["-y", "firecrawl-mcp"])
        XCTAssertEqual(firecrawlTransport.env, ["FIRECRAWL_API_KEY": ""])
    }

    func testMergeRefreshedModelsUsesLatestPersistedDuplicateForUserPreferences() {
        let existingModels = [
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 old",
                capabilities: [.streaming],
                contextWindow: 128_000,
                overrides: nil,
                isEnabled: true
            ),
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 newer",
                capabilities: [.streaming],
                contextWindow: 128_000,
                overrides: ModelOverrides(contextWindow: 64_000),
                isEnabled: false
            ),
        ]

        let latestModels = [
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 refreshed",
                capabilities: [.streaming, .toolCalling],
                contextWindow: 256_000,
                catalogMetadata: ModelCatalogMetadata(
                    availabilityMessage: "Limited runs",
                    upgradeTargetModelID: "gpt-4.2",
                    upgradeMessage: "Upgrade available"
                )
            ),
        ]

        let merged = AppPostLaunchMaintenance.mergeRefreshedModels(
            latestModels: latestModels,
            existingModels: existingModels
        )
        XCTAssertEqual(merged.count, 1)

        guard let model = merged.first else {
            return XCTFail("Expected one merged model")
        }
        XCTAssertEqual(model.name, "GPT-4.1 refreshed")
        XCTAssertEqual(model.contextWindow, 256_000)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.overrides?.contextWindow, 64_000)
        XCTAssertEqual(model.catalogMetadata?.upgradeTargetModelID, "gpt-4.2")
        XCTAssertEqual(model.catalogMetadata?.availabilityMessage, "Limited runs")
        XCTAssertEqual(model.catalogMetadata?.upgradeMessage, "Upgrade available")
    }

    func testMergeRefreshedModelsDeduplicatesLatestProviderPayload() {
        let latestModels = [
            ModelInfo(
                id: "duplicate-model",
                name: "First",
                capabilities: [.streaming],
                contextWindow: 4_096
            ),
            ModelInfo(
                id: "duplicate-model",
                name: "Second",
                capabilities: [.toolCalling],
                contextWindow: 8_192
            ),
            ModelInfo(
                id: "new-model",
                name: "New Model",
                capabilities: [.reasoning],
                contextWindow: 32_768
            ),
        ]

        let merged = AppPostLaunchMaintenance.mergeRefreshedModels(latestModels: latestModels, existingModels: [])
        XCTAssertEqual(merged.map(\.id), ["duplicate-model", "new-model"])

        let duplicate = merged[0]
        XCTAssertEqual(duplicate.name, "First")
        XCTAssertEqual(duplicate.contextWindow, 4_096)
        XCTAssertTrue(duplicate.isEnabled)
    }

    func testJinAppMergeRefreshedModelsDelegatesToPostLaunchMaintenancePolicy() {
        let latestModels = [
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 refreshed",
                capabilities: [.streaming, .toolCalling],
                contextWindow: 256_000
            )
        ]
        let existingModels = [
            ModelInfo(
                id: "gpt-4.1",
                name: "GPT-4.1 old",
                capabilities: [.streaming],
                contextWindow: 128_000,
                overrides: ModelOverrides(contextWindow: 64_000),
                isEnabled: false
            )
        ]

        let appMerged = JinApp.mergeRefreshedModels(latestModels: latestModels, existingModels: existingModels)
        let maintenanceMerged = AppPostLaunchMaintenance.mergeRefreshedModels(
            latestModels: latestModels,
            existingModels: existingModels
        )

        XCTAssertEqual(appMerged.map(\.id), maintenanceMerged.map(\.id))
        XCTAssertEqual(appMerged.first?.name, maintenanceMerged.first?.name)
        XCTAssertEqual(appMerged.first?.contextWindow, maintenanceMerged.first?.contextWindow)
        XCTAssertEqual(appMerged.first?.overrides?.contextWindow, maintenanceMerged.first?.overrides?.contextWindow)
        XCTAssertEqual(appMerged.first?.isEnabled, maintenanceMerged.first?.isEnabled)
    }
}
