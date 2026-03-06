import Foundation

enum LegacyOpenAIMaxOutputMigration {
    static let legacyBugDefaultMaxOutputTokens = 4096

    static func shouldClearAssistantMaxOutputTokens(_ value: Int?, assistantID: String) -> Bool {
        assistantID == "default" && value == legacyBugDefaultMaxOutputTokens
    }

    static func migratedControlsIfNeeded(
        _ controls: GenerationControls,
        providerType: ProviderType?,
        modelID: String,
        assistantMaxOutputTokens: Int?
    ) -> GenerationControls? {
        guard assistantMaxOutputTokens == nil else { return nil }
        guard controls.maxTokens == legacyBugDefaultMaxOutputTokens else { return nil }
        guard let providerType, providerType == .openai || providerType == .openaiWebSocket else { return nil }
        guard let modelMaxOutputTokens = ModelCatalog.entry(for: modelID, provider: providerType)?.maxOutputTokens,
              modelMaxOutputTokens > legacyBugDefaultMaxOutputTokens else {
            return nil
        }

        var migrated = controls
        migrated.maxTokens = nil
        return migrated
    }
}
