import SwiftUI
import SwiftData

@main
struct JinApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var streamingStore = ConversationStreamingStore()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: ConversationEntity.self,
                AssistantEntity.self,
                MessageEntity.self,
                ProviderConfigEntity.self,
                MCPServerConfigEntity.self,
                AttachmentEntity.self
            )
            seedDefaultMCPServersIfNeeded()
            updateProviderModelsIfNeeded()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(streamingStore)
        }
        .modelContainer(modelContainer)
        .commands {
            ChatCommands()
        }

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
    }

    private func seedDefaultMCPServersIfNeeded() {
        let context = ModelContext(modelContainer)

        func hasServer(id: String) -> Bool {
            let descriptor = FetchDescriptor<MCPServerConfigEntity>(
                predicate: #Predicate { $0.id == id }
            )
            return ((try? context.fetchCount(descriptor)) ?? 0) > 0
        }

        func seedIfMissing(id: String, name: String, command: String, args: [String], env: [String: String]) {
            guard !hasServer(id: id) else { return }

            let argsData = (try? JSONEncoder().encode(args)) ?? Data()
            let envData = env.isEmpty ? nil : (try? JSONEncoder().encode(env))

            let server = MCPServerConfigEntity(
                id: id,
                name: name,
                command: command,
                argsData: argsData,
                envData: envData,
                isEnabled: false,
                runToolsAutomatically: true,
                isLongRunning: true
            )

            context.insert(server)
        }

        seedIfMissing(
            id: "firecrawl",
            name: "Firecrawl",
            command: "npx",
            args: ["-y", "firecrawl-mcp"],
            env: ["FIRECRAWL_API_KEY": ""]
        )
        seedIfMissing(
            id: "exa",
            name: "Exa",
            command: "npx",
            args: ["-y", "exa-mcp-server"],
            env: ["EXA_API_KEY": ""]
        )

        try? context.save()
    }

    private func updateProviderModelsIfNeeded() {
        Task {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<ProviderConfigEntity>()

            guard let providers = try? context.fetch(descriptor) else { return }

            let providerManager = ProviderManager()

            for providerEntity in providers {
                do {
                    // Convert to domain model
                    let providerConfig = try providerEntity.toDomain()

                    // Create adapter and fetch latest models
                    let adapter = try await providerManager.createAdapter(for: providerConfig)
                    let latestModels = try await adapter.fetchAvailableModels()

                    // Update modelsData with latest capabilities
                    let encoder = JSONEncoder()
                    if let newModelsData = try? encoder.encode(latestModels) {
                        providerEntity.modelsData = newModelsData
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
