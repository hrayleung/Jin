import SwiftUI
import SwiftData
import AppKit
import Kingfisher

@MainActor
private final class JinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        CodexAppServerController.shared.shutdownForApplicationTermination()
    }
}

@main
struct JinApp: App {
    private let modelContainer: ModelContainer
    @NSApplicationDelegateAdaptor(JinAppDelegate.self) private var appDelegate
    @StateObject private var streamingStore = ConversationStreamingStore()
    @StateObject private var responseCompletionNotifier = ResponseCompletionNotifier()
    @StateObject private var shortcutsStore = AppShortcutsStore.shared
    @StateObject private var updateManager: SparkleUpdateManager

    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.appIconVariant) private var appIconVariant: AppIconVariant = .roseQuartz

    private let mcpSchemaVersionPreferenceKey = "mcpTransportSchemaVersion"
    private let mcpSchemaVersion = 2

    init() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKeys.notifyOnBackgroundResponseCompletion: true,
            AppPreferenceKeys.updateAutoCheckOnLaunch: true,
            AppPreferenceKeys.updateAllowPreRelease: false,
            AppPreferenceKeys.codexWorkingDirectoryPresetsJSON: "[]"
        ])
        ImageCache.default.memoryStorage.config.expiration = .seconds(3600)
        ImageCache.default.diskStorage.config.expiration = .days(30)

        _updateManager = StateObject(wrappedValue: SparkleUpdateManager())
        do {
            modelContainer = try ModelContainer(
                for: ConversationEntity.self,
                ConversationModelThreadEntity.self,
                AssistantEntity.self,
                MessageEntity.self,
                ProviderConfigEntity.self,
                MCPServerConfigEntity.self,
                AttachmentEntity.self
            )
            resetMCPServersForTransportV2IfNeeded()
            updateProviderModelsIfNeeded()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(streamingStore)
                .environmentObject(responseCompletionNotifier)
                .environmentObject(shortcutsStore)
                .environmentObject(updateManager)
                .font(JinTypography.appFont(familyPreference: appFontFamily))
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    AppIconManager.apply(appIconVariant)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(modelContainer)
        .commands {
            ChatCommands(shortcutsStore: shortcutsStore)
        }

        Settings {
            SettingsView()
                .environmentObject(responseCompletionNotifier)
                .environmentObject(shortcutsStore)
                .environmentObject(updateManager)
                .font(JinTypography.appFont(familyPreference: appFontFamily))
                .preferredColorScheme(preferredColorScheme)
        }
        .modelContainer(modelContainer)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appAppearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func resetMCPServersForTransportV2IfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: mcpSchemaVersionPreferenceKey) < mcpSchemaVersion else {
            return
        }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MCPServerConfigEntity>()
        if let existing = try? context.fetch(descriptor) {
            for server in existing {
                context.delete(server)
            }
        }

        var seedFailed = false
        func seedServer(
            id: String,
            name: String,
            transport: MCPTransportConfig,
            isEnabled: Bool = false,
            runToolsAutomatically: Bool = true
        ) {
            do {
                let transportData = try JSONEncoder().encode(transport)
                let server = MCPServerConfigEntity(
                    id: id,
                    name: name,
                    transportKindRaw: transport.kind.rawValue,
                    transportData: transportData,
                    lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
                    isEnabled: isEnabled,
                    runToolsAutomatically: runToolsAutomatically,
                    isLongRunning: true
                )
                try server.setTransport(transport)
                context.insert(server)
            } catch {
                seedFailed = true
                assertionFailure("Failed to seed MCP server \"\(id)\": \(error)")
            }
        }

        seedServer(
            id: "firecrawl",
            name: "Firecrawl",
            transport: .stdio(
                MCPStdioTransportConfig(
                    command: "npx",
                    args: ["-y", "firecrawl-mcp"],
                    env: ["FIRECRAWL_API_KEY": ""]
                )
            )
        )

        if let exaEndpoint = URL(string: "https://mcp.exa.ai/mcp") {
            seedServer(
                id: "exa",
                name: "Exa",
                transport: .http(
                    MCPHTTPTransportConfig(
                        endpoint: exaEndpoint,
                        streaming: true,
                        authentication: .none,
                        additionalHeaders: [MCPHeader(name: "X-Client", value: "jin")]
                    )
                )
            )
        }

        guard !seedFailed else { return }
        do {
            try context.save()
            defaults.set(mcpSchemaVersion, forKey: mcpSchemaVersionPreferenceKey)
        } catch {
            assertionFailure("Failed to save MCP schema migration: \(error)")
        }
    }

    private func updateProviderModelsIfNeeded() {
        let defaults = UserDefaults.standard
        let refreshInterval: TimeInterval = 24 * 60 * 60

        Task {
            let now = Date()
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<ProviderConfigEntity>()

            guard let providers = try? context.fetch(descriptor) else { return }

            let providerManager = ProviderManager()

            // Collect providers that need refresh with their current configs
            var staleProviders: [(entity: ProviderConfigEntity, config: ProviderConfig, existingModels: [ModelInfo])] = []
            for providerEntity in providers {
                let refreshKey = "providerModelsLastRefreshAt.\(providerEntity.id)"
                let lastRefreshedAt = defaults.double(forKey: refreshKey)
                if lastRefreshedAt > 0,
                   now.timeIntervalSince1970 - lastRefreshedAt < refreshInterval {
                    continue
                }
                guard let config = try? providerEntity.toDomain() else { continue }
                staleProviders.append((providerEntity, config, providerEntity.allModels))
            }

            // Fetch models from all stale providers concurrently
            let fetchResults = await withTaskGroup(
                of: (id: String, models: [ModelInfo]?).self,
                returning: [String: [ModelInfo]].self
            ) { group in
                for entry in staleProviders {
                    group.addTask {
                        do {
                            let adapter = try await providerManager.createAdapter(for: entry.config)
                            let models = try await adapter.fetchAvailableModels()
                            return (entry.config.id, models)
                        } catch {
                            return (entry.config.id, nil)
                        }
                    }
                }
                var results: [String: [ModelInfo]] = [:]
                for await result in group {
                    if let models = result.models {
                        results[result.id] = models
                    }
                }
                return results
            }

            // Merge results back into SwiftData entities (sequential, same context)
            let encoder = JSONEncoder()
            for entry in staleProviders {
                guard let latestModels = fetchResults[entry.config.id] else { continue }
                let merged = Self.mergeRefreshedModels(
                    latestModels: latestModels,
                    existingModels: entry.existingModels
                )
                if let newModelsData = try? encoder.encode(merged) {
                    entry.entity.modelsData = newModelsData
                    defaults.set(now.timeIntervalSince1970, forKey: "providerModelsLastRefreshAt.\(entry.entity.id)")
                }
            }

            try? context.save()
        }
    }

    static func mergeRefreshedModels(latestModels: [ModelInfo], existingModels: [ModelInfo]) -> [ModelInfo] {
        // Duplicate IDs can exist in legacy persisted data; latest duplicate wins.
        let existingByID = existingModels.reduce(into: [String: ModelInfo]()) { result, model in
            result[model.id] = model
        }

        // Provider responses may occasionally include duplicate IDs; keep first in fetch order.
        var seenLatestIDs = Set<String>()
        var merged: [ModelInfo] = []
        merged.reserveCapacity(latestModels.count)

        for model in latestModels {
            guard seenLatestIDs.insert(model.id).inserted else { continue }

            let existing = existingByID[model.id]
            merged.append(
                ModelInfo(
                    id: model.id,
                    name: model.name,
                    capabilities: model.capabilities,
                    contextWindow: model.contextWindow,
                    maxOutputTokens: model.maxOutputTokens,
                    reasoningConfig: model.reasoningConfig,
                    overrides: existing?.overrides,
                    catalogMetadata: model.catalogMetadata,
                    isEnabled: existing?.isEnabled ?? true
                )
            )
        }

        return merged
    }
}
