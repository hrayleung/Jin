import SwiftUI
import SwiftData
import AppKit

@MainActor
private final class JinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        CodexAppServerController.shared.stop()
    }
}

@main
struct JinApp: App {
    private let modelContainer: ModelContainer
    @NSApplicationDelegateAdaptor(JinAppDelegate.self) private var appDelegate
    @StateObject private var streamingStore = ConversationStreamingStore()
    @StateObject private var responseCompletionNotifier = ResponseCompletionNotifier()
    @StateObject private var shortcutsStore = AppShortcutsStore.shared
    @StateObject private var updateManager = SparkleUpdateManager()

    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.appIconVariant) private var appIconVariant: AppIconVariant = .roseQuartz

    private let mcpSchemaVersionPreferenceKey = "mcpTransportSchemaVersion"
    private let mcpSchemaVersion = 2

    init() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKeys.notifyOnBackgroundResponseCompletion: true,
            AppPreferenceKeys.updateAutoCheckOnLaunch: true,
            AppPreferenceKeys.updateAllowPreRelease: false
        ])
        do {
            modelContainer = try ModelContainer(
                for: ConversationEntity.self,
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

        func seedServer(
            id: String,
            name: String,
            transport: MCPTransportConfig,
            isEnabled: Bool = false,
            runToolsAutomatically: Bool = true
        ) {
            let transportData = (try? JSONEncoder().encode(transport)) ?? Data()
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
            server.setTransport(transport)
            context.insert(server)
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

        try? context.save()
        defaults.set(mcpSchemaVersion, forKey: mcpSchemaVersionPreferenceKey)
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

            for providerEntity in providers {
                do {
                    let refreshKey = "providerModelsLastRefreshAt.\(providerEntity.id)"
                    let lastRefreshedAt = defaults.double(forKey: refreshKey)
                    if lastRefreshedAt > 0,
                       now.timeIntervalSince1970 - lastRefreshedAt < refreshInterval {
                        continue
                    }

                    // Convert to domain model
                    let providerConfig = try providerEntity.toDomain()

                    // Create adapter and fetch latest models
                    let adapter = try await providerManager.createAdapter(for: providerConfig)
                    let latestModels = try await adapter.fetchAvailableModels()

                    // Preserve user enable/disable choices when refreshing model metadata.
                    let existingByID = Dictionary(uniqueKeysWithValues: providerEntity.allModels.map { ($0.id, $0) })
                    let merged = latestModels.map { model in
                        let isEnabled = existingByID[model.id]?.isEnabled ?? true
                        let overrides = existingByID[model.id]?.overrides
                        return ModelInfo(
                            id: model.id,
                            name: model.name,
                            capabilities: model.capabilities,
                            contextWindow: model.contextWindow,
                            reasoningConfig: model.reasoningConfig,
                            overrides: overrides,
                            isEnabled: isEnabled
                        )
                    }

                    let encoder = JSONEncoder()
                    if let newModelsData = try? encoder.encode(merged) {
                        providerEntity.modelsData = newModelsData
                        defaults.set(now.timeIntervalSince1970, forKey: refreshKey)
                    }
                } catch {
                    // If fetching fails, continue with next provider
                    continue
                }
            }

            try? context.save()
        }
    }
}
