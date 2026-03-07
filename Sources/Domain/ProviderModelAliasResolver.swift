import Foundation

enum ProviderModelAliasResolver {
    static func resolvedModel(
        for requestedModelID: String,
        providerType: ProviderType?,
        availableModels: [ModelInfo]
    ) -> ModelInfo? {
        if let exact = availableModels.first(where: { $0.id == requestedModelID }) {
            return exact
        }

        let normalizedRequested = normalizedLookupKey(requestedModelID)
        if let exactCaseInsensitive = availableModels.first(where: { normalizedLookupKey($0.id) == normalizedRequested }) {
            return exactCaseInsensitive
        }

        guard providerType == .githubCopilot else { return nil }

        let matches = availableModels.filter {
            normalizedGitHubSuffix($0.id) == normalizedRequested
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func resolvedModelID(
        for requestedModelID: String,
        providerType: ProviderType?,
        availableModels: [ModelInfo]
    ) -> String {
        resolvedModel(for: requestedModelID, providerType: providerType, availableModels: availableModels)?.id ?? requestedModelID
    }

    private static func normalizedLookupKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedGitHubSuffix(_ raw: String) -> String {
        let normalized = normalizedLookupKey(raw)
        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }
}
