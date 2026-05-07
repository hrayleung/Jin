import Foundation

extension CodeExecutionSheetSupport {
    static func supportsConfiguration(for providerType: ProviderType?) -> Bool {
        providerSupportsOpenAIContainerSettings(providerType) || providerType == .anthropic
    }

    static func isDraftValid(
        providerType: ProviderType?,
        openAIUseExistingContainer: Bool,
        openAI: OpenAICodeExecutionOptions?
    ) -> Bool {
        guard providerSupportsOpenAIContainerSettings(providerType),
              openAIUseExistingContainer else {
            return true
        }
        return openAI?.normalizedExistingContainerID != nil
    }

    static func providerSupportsOpenAIContainerSettings(_ providerType: ProviderType?) -> Bool {
        providerType == .openai || providerType == .openaiWebSocket
    }
}
