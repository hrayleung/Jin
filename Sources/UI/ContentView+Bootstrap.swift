import SwiftUI
import SwiftData

// MARK: - Bootstrap & Migration

extension ContentView {
    @MainActor
    func bootstrapDefaultProvidersIfNeeded() {
        guard !didBootstrapDefaults else { return }
        didBootstrapDefaults = true

        let descriptor = FetchDescriptor<ProviderConfigEntity>()
        guard let persistedProviders = try? modelContext.fetch(descriptor) else {
            return
        }

        var didUpdateProviderIcon = false

        for provider in persistedProviders {
            let current = provider.iconID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == nil || current?.isEmpty == true else { continue }
            guard let providerType = ProviderType(rawValue: provider.typeRaw) else { continue }
            provider.iconID = LobeProviderIconCatalog.defaultIconID(for: providerType)
            didUpdateProviderIcon = true
        }

        if didUpdateProviderIcon {
            try? modelContext.save()
        }

        let persistedIDs = Set(persistedProviders.map(\.id))
        let missingDefaults = DefaultProviderSeeds.allProviders().filter { !persistedIDs.contains($0.id) }

        for config in missingDefaults {
            if let entity = try? ProviderConfigEntity.fromDomain(config) {
                modelContext.insert(entity)
            }
        }

        if !missingDefaults.isEmpty {
            try? modelContext.save()
        }
    }

    @MainActor
    func bootstrapDefaultAssistantsIfNeeded() {
        guard !didBootstrapAssistants else { return }
        didBootstrapAssistants = true

        migrateLegacyOpenAIMaxOutputDefaultsIfNeeded()

        let defaultAssistant: AssistantEntity
        if let existing = assistants.first(where: { $0.id == "default" }) {
            defaultAssistant = existing
        } else {
            let created = AssistantEntity(
                id: "default",
                name: "Default",
                icon: "laptopcomputer",
                assistantDescription: "General-purpose assistant.",
                systemInstruction: "",
                temperature: 0.1,
                maxOutputTokens: nil,
                truncateMessages: nil,
                replyLanguage: nil,
                sortOrder: 0
            )
            modelContext.insert(created)
            defaultAssistant = created
        }

        if selectedAssistant == nil {
            selectedAssistant = defaultAssistant
        }

        for conversation in conversations where conversation.assistant == nil {
            conversation.assistant = defaultAssistant
        }
    }

    @MainActor
    func migrateLegacyOpenAIMaxOutputDefaultsIfNeeded() {
        guard !didRunLegacyOpenAIMaxOutputMigration else { return }

        var didMutate = false

        if let defaultAssistant = assistants.first(where: { $0.id == "default" }),
           LegacyOpenAIMaxOutputMigration.shouldClearAssistantMaxOutputTokens(
            defaultAssistant.maxOutputTokens,
            assistantID: defaultAssistant.id
           ) {
            defaultAssistant.maxOutputTokens = nil
            defaultAssistant.updatedAt = Date()
            didMutate = true
        }

        for conversation in conversations {
            let assistantMaxOutputTokens = conversation.assistant?.maxOutputTokens

            if let migrated = migratedModelConfigDataIfNeeded(
                conversation.modelConfigData,
                providerID: conversation.providerID,
                modelID: conversation.modelID,
                assistantMaxOutputTokens: assistantMaxOutputTokens
            ) {
                conversation.modelConfigData = migrated
                didMutate = true
            }

            for thread in conversation.modelThreads {
                if let migrated = migratedModelConfigDataIfNeeded(
                    thread.modelConfigData,
                    providerID: thread.providerID,
                    modelID: thread.modelID,
                    assistantMaxOutputTokens: assistantMaxOutputTokens
                ) {
                    thread.modelConfigData = migrated
                    didMutate = true
                }
            }
        }

        if didMutate {
            try? modelContext.save()
        }

        didRunLegacyOpenAIMaxOutputMigration = true
    }

    func migratedModelConfigDataIfNeeded(
        _ data: Data,
        providerID: String,
        modelID: String,
        assistantMaxOutputTokens: Int?
    ) -> Data? {
        guard let providerType = providers.first(where: { $0.id == providerID })
            .flatMap({ ProviderType(rawValue: $0.typeRaw) }) else {
            return nil
        }
        guard let controls = try? JSONDecoder().decode(GenerationControls.self, from: data) else {
            return nil
        }
        guard let migrated = LegacyOpenAIMaxOutputMigration.migratedControlsIfNeeded(
            controls,
            providerType: providerType,
            modelID: modelID,
            assistantMaxOutputTokens: assistantMaxOutputTokens
        ) else {
            return nil
        }
        return try? JSONEncoder().encode(migrated)
    }
}
