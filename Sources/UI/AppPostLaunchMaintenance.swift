import Collections
import Foundation
import SwiftData

@MainActor
final class AppPostLaunchMaintenance {
    private let defaults: UserDefaults
    private let providerManager: ProviderManager
    private let mcpSchemaVersionPreferenceKey = "mcpTransportSchemaVersion"
    private let mcpSchemaVersion = 2
    private let providerModelRefreshInterval: TimeInterval = 24 * 60 * 60

    init(
        defaults: UserDefaults = .standard,
        providerManager: ProviderManager = ProviderManager()
    ) {
        self.defaults = defaults
        self.providerManager = providerManager
    }

    func perform(with container: ModelContainer) {
        resetMCPServersForTransportV2IfNeeded(container: container)
        updateProviderModelsIfNeeded(container: container)
    }

    func resetMCPServersForTransportV2IfNeeded(container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<MCPServerConfigEntity>()
        let existingServers = (try? context.fetch(descriptor)) ?? []

        let needsSchemaMigration = defaults.integer(forKey: mcpSchemaVersionPreferenceKey) < mcpSchemaVersion
        let databaseIsEmpty = existingServers.isEmpty

        guard needsSchemaMigration || databaseIsEmpty else { return }

        if needsSchemaMigration {
            for server in existingServers {
                context.delete(server)
            }
        }

        guard seedDefaultMCPServers(in: context) else { return }
        do {
            try context.save()
            defaults.set(mcpSchemaVersion, forKey: mcpSchemaVersionPreferenceKey)
        } catch {
            assertionFailure("Failed to save MCP schema migration: \(error)")
        }
    }

    func updateProviderModelsIfNeeded(container: ModelContainer) {
        Task {
            await refreshStaleProviderModels(in: container, now: Date())
        }
    }

    nonisolated static func mergeRefreshedModels(latestModels: [ModelInfo], existingModels: [ModelInfo]) -> [ModelInfo] {
        let existingByID = existingModels.reduce(into: [String: ModelInfo]()) { result, model in
            result[model.id] = model
        }

        var seenLatestIDs = OrderedSet<String>()
        var merged: [ModelInfo] = []
        merged.reserveCapacity(latestModels.count)

        for model in latestModels {
            guard !seenLatestIDs.contains(model.id) else { continue }
            seenLatestIDs.append(model.id)

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

    private func seedDefaultMCPServers(in context: ModelContext) -> Bool {
        var seedFailed = false

        for seed in Self.defaultMCPServerSeeds {
            do {
                let transportData = try JSONEncoder().encode(seed.transport)
                let server = MCPServerConfigEntity(
                    id: seed.id,
                    name: seed.name,
                    transportKindRaw: seed.transport.kind.rawValue,
                    transportData: transportData,
                    lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
                    isEnabled: seed.isEnabled,
                    runToolsAutomatically: seed.runToolsAutomatically,
                    isLongRunning: true
                )
                try server.setTransport(seed.transport)
                context.insert(server)
            } catch {
                seedFailed = true
                assertionFailure("Failed to seed MCP server \"\(seed.id)\": \(error)")
            }
        }

        return !seedFailed
    }

    private func refreshStaleProviderModels(in container: ModelContainer, now: Date) async {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ProviderConfigEntity>()

        guard let providers = try? context.fetch(descriptor) else { return }

        let staleProviders = staleProviderRefreshEntries(from: providers, now: now)
        guard !staleProviders.isEmpty else { return }

        let fetchResults = await fetchLatestModels(for: staleProviders)
        apply(fetchResults: fetchResults, to: staleProviders, now: now)
        try? context.save()
    }

    private func staleProviderRefreshEntries(
        from providers: [ProviderConfigEntity],
        now: Date
    ) -> [ProviderRefreshEntry] {
        providers.compactMap { providerEntity in
            guard shouldRefreshProviderModels(providerID: providerEntity.id, now: now),
                  let config = try? providerEntity.toDomain() else {
                return nil
            }
            return ProviderRefreshEntry(
                entity: providerEntity,
                config: config,
                existingModels: providerEntity.allModels
            )
        }
    }

    private func shouldRefreshProviderModels(providerID: String, now: Date) -> Bool {
        let lastRefreshedAt = defaults.double(forKey: providerRefreshPreferenceKey(for: providerID))
        guard lastRefreshedAt > 0 else { return true }
        return now.timeIntervalSince1970 - lastRefreshedAt >= providerModelRefreshInterval
    }

    private func fetchLatestModels(
        for staleProviders: [ProviderRefreshEntry]
    ) async -> [String: [ModelInfo]] {
        await withTaskGroup(
            of: (id: String, models: [ModelInfo]?).self,
            returning: [String: [ModelInfo]].self
        ) { group in
            for entry in staleProviders {
                group.addTask {
                    do {
                        let adapter = try await self.providerManager.createAdapter(for: entry.config)
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
    }

    private func apply(
        fetchResults: [String: [ModelInfo]],
        to staleProviders: [ProviderRefreshEntry],
        now: Date
    ) {
        let encoder = JSONEncoder()
        for entry in staleProviders {
            guard let latestModels = fetchResults[entry.config.id] else { continue }
            let merged = Self.mergeRefreshedModels(
                latestModels: latestModels,
                existingModels: entry.existingModels
            )
            if let newModelsData = try? encoder.encode(merged) {
                entry.entity.modelsData = newModelsData
                defaults.set(now.timeIntervalSince1970, forKey: providerRefreshPreferenceKey(for: entry.entity.id))
            }
        }
    }

    private func providerRefreshPreferenceKey(for providerID: String) -> String {
        "providerModelsLastRefreshAt.\(providerID)"
    }
}

private struct ProviderRefreshEntry {
    let entity: ProviderConfigEntity
    let config: ProviderConfig
    let existingModels: [ModelInfo]
}

private struct MCPServerSeed {
    let id: String
    let name: String
    let transport: MCPTransportConfig
    let isEnabled: Bool
    let runToolsAutomatically: Bool
}

private extension AppPostLaunchMaintenance {
    static var defaultMCPServerSeeds: [MCPServerSeed] {
        var seeds = [
            MCPServerSeed(
                id: "firecrawl",
                name: "Firecrawl",
                transport: .stdio(
                    MCPStdioTransportConfig(
                        command: "npx",
                        args: ["-y", "firecrawl-mcp"],
                        env: ["FIRECRAWL_API_KEY": ""]
                    )
                ),
                isEnabled: false,
                runToolsAutomatically: true
            )
        ]

        if let exaEndpoint = URL(string: "https://mcp.exa.ai/mcp") {
            seeds.append(
                MCPServerSeed(
                    id: "exa",
                    name: "Exa",
                    transport: .http(
                        MCPHTTPTransportConfig(
                            endpoint: exaEndpoint,
                            streaming: true,
                            authentication: .none,
                            additionalHeaders: [MCPHeader(name: "X-Client", value: "jin")]
                        )
                    ),
                    isEnabled: false,
                    runToolsAutomatically: true
                )
            )
        }

        return seeds
    }
}
