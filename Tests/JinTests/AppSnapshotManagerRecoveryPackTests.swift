import Foundation
import SwiftData
import XCTest
@testable import Jin

final class AppSnapshotManagerRecoveryPackTests: XCTestCase {
    private var previousAppSupportRoot: String?
    private var preservedDomains: [String: [String: Any]] = [:]
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        previousAppSupportRoot = ProcessInfo.processInfo.environment["JIN_APP_SUPPORT_ROOT"]
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        setenv("JIN_APP_SUPPORT_ROOT", temporaryRoot.path, 1)

        let defaults = UserDefaults.standard
        for domainName in preferenceDomainNames(defaults: defaults) {
            if let preserved = defaults.persistentDomain(forName: domainName) {
                preservedDomains[domainName] = preserved
            }
            defaults.removePersistentDomain(forName: domainName)
        }
        defaults.synchronize()

        AppSnapshotManager.clearAcceptedCurrentState()
        try AppDataLocations.ensureDirectoriesExist()
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for domainName in preferenceDomainNames(defaults: defaults) {
            if let preserved = preservedDomains[domainName] {
                defaults.setPersistentDomain(preserved, forName: domainName)
            } else {
                defaults.removePersistentDomain(forName: domainName)
            }
        }
        defaults.synchronize()

        if let previousAppSupportRoot {
            setenv("JIN_APP_SUPPORT_ROOT", previousAppSupportRoot, 1)
        } else {
            unsetenv("JIN_APP_SUPPORT_ROOT")
        }

        try? FileManager.default.removeItem(at: temporaryRoot)
        AppSnapshotManager.clearAcceptedCurrentState()
        preservedDomains.removeAll()
    }

    func testRecoveryPackRoundTripsMCPServersAndPluginPreferences() throws {
        try seedProviderAndMCPServer()
        AppPreferencesSnapshotStore.applyPreferenceDictionary([
            AppPreferenceKeys.pluginWebSearchEnabled: true,
            AppPreferenceKeys.pluginWebSearchExaAPIKey: "exa-test-key",
            AppPreferenceKeys.newChatFixedMCPServerIDsJSON: AppPreferences.encodeStringArrayJSON(["local-test"]),
            "mcpTransportSchemaVersion": 2
        ])

        let archiveURL = temporaryRoot.appendingPathComponent("roundtrip.jinbackup", isDirectory: false)
        try AppSnapshotManager.exportRecoveryArchive(to: archiveURL)

        let mutatedContainer = try PersistenceContainerFactory.makeContainer()
        let mutatedContext = ModelContext(mutatedContainer)
        try mutatedContext.delete(model: ProviderConfigEntity.self)
        try mutatedContext.delete(model: MCPServerConfigEntity.self)
        try mutatedContext.save()
        AppPreferencesSnapshotStore.applyPreferenceDictionary([
            AppPreferenceKeys.pluginWebSearchEnabled: false,
            AppPreferenceKeys.pluginWebSearchExaAPIKey: "different-key",
            AppPreferenceKeys.newChatFixedMCPServerIDsJSON: "[]",
            "mcpTransportSchemaVersion": 0
        ])

        try AppSnapshotManager.queueImportArchiveForRestore(from: archiveURL)
        let restoredContainer = try readyContainerAfterStartupEvaluation()
        let restoredContext = ModelContext(restoredContainer)

        let providers = try restoredContext.fetch(FetchDescriptor<ProviderConfigEntity>())
        let mcpServers = try restoredContext.fetch(FetchDescriptor<MCPServerConfigEntity>())

        XCTAssertEqual(providers.map(\.id), ["openai"])
        XCTAssertEqual(mcpServers.map(\.id), ["local-test"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppPreferenceKeys.pluginWebSearchEnabled))
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginWebSearchExaAPIKey), "exa-test-key")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppPreferenceKeys.newChatFixedMCPServerIDsJSON),
            AppPreferences.encodeStringArrayJSON(["local-test"])
        )
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "mcpTransportSchemaVersion"), 2)
    }

    func testRecoveryPackRestoresManagedPreferencesDirectoryContents() throws {
        try seedProviderAndMCPServer()

        let preferencesDirectory = try AppDataLocations.preferencesDirectoryURL()
        let pluginStateURL = preferencesDirectory.appendingPathComponent("plugin-state.json", isDirectory: false)
        try XCTUnwrap("{\"enabled\":true}".data(using: .utf8)).write(to: pluginStateURL, options: .atomic)

        let archiveURL = temporaryRoot.appendingPathComponent("preferences-dir.jinbackup", isDirectory: false)
        try AppSnapshotManager.exportRecoveryArchive(to: archiveURL)

        try XCTUnwrap("{\"enabled\":false}".data(using: .utf8)).write(to: pluginStateURL, options: .atomic)

        try AppSnapshotManager.queueImportArchiveForRestore(from: archiveURL)
        _ = try readyContainerAfterStartupEvaluation()

        let restoredData = try Data(contentsOf: pluginStateURL)
        XCTAssertEqual(String(data: restoredData, encoding: .utf8), "{\"enabled\":true}")
    }

    func testRecoveryPackRemovesLiveAttachmentsWhenSnapshotDidNotContainAny() throws {
        try seedProviderAndMCPServer()

        let attachmentsDirectory = try AppDataLocations.attachmentsDirectoryURL()
        try FileManager.default.removeItem(at: attachmentsDirectory)

        let archiveURL = temporaryRoot.appendingPathComponent("no-attachments.jinbackup", isDirectory: false)
        try AppSnapshotManager.exportRecoveryArchive(to: archiveURL)

        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let strayAttachmentURL = attachmentsDirectory.appendingPathComponent("stale.txt", isDirectory: false)
        try XCTUnwrap("stale".data(using: .utf8)).write(to: strayAttachmentURL, options: .atomic)

        try AppSnapshotManager.queueImportArchiveForRestore(from: archiveURL)
        _ = try readyContainerAfterStartupEvaluation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: strayAttachmentURL.path))
    }

    private func seedProviderAndMCPServer() throws {
        let container = try PersistenceContainerFactory.makeContainer()
        let context = ModelContext(container)

        let openAI = try XCTUnwrap(DefaultProviderSeeds.allProviders().first(where: { $0.id == "openai" }))
        context.insert(try ProviderConfigEntity.fromDomain(openAI))

        let transport = MCPTransportConfig.stdio(
            MCPStdioTransportConfig(
                command: "npx",
                args: ["-y", "local-test-mcp"],
                env: ["LOCAL_TEST_KEY": "value"]
            )
        )
        let server = MCPServerConfigEntity(
            id: "local-test",
            name: "Local Test",
            transportKindRaw: MCPTransportKind.stdio.rawValue,
            transportData: try JSONEncoder().encode(transport),
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: true,
            runToolsAutomatically: false,
            isLongRunning: true
        )
        try server.setTransport(transport)
        context.insert(server)
        try context.save()
    }

    private func readyContainerAfterStartupEvaluation() throws -> ModelContainer {
        let evaluation = try AppSnapshotManager.evaluateCurrentStoreForStartup()
        guard case .ready(let container) = evaluation else {
            XCTFail("Expected startup evaluation to return a ready container.")
            throw SnapshotError.invalidSnapshot("Startup evaluation did not return a ready container.")
        }
        return container
    }

    private func preferenceDomainNames(defaults: UserDefaults) -> [String] {
        [
            AppDataLocations.sharedDirectoryName,
            "Jin",
            AppPreferencesSnapshotStore.currentDomainName(defaults: defaults)
        ]
    }
}
