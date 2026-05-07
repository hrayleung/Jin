import Foundation

extension ChatAuxiliaryControlSupport {
    static func webSearchSourceIsSelected(
        _ source: WebSearchSource,
        controls: GenerationControls
    ) -> Bool {
        Set(controls.webSearch?.sources ?? []).contains(source)
    }

    static func webSearchEnabledValue(
        providerType: ProviderType?,
        controls: GenerationControls
    ) -> Bool {
        if providerType == .perplexity {
            return controls.webSearch?.enabled ?? true
        }
        return controls.webSearch?.enabled ?? false
    }

    static func setWebSearchEnabled(
        _ isEnabled: Bool,
        controls: GenerationControls,
        providerType: ProviderType?
    ) -> GenerationControls {
        var controls = controls
        if controls.webSearch == nil {
            controls.webSearch = ChatControlNormalizationSupport.defaultWebSearchControls(
                enabled: isEnabled,
                providerType: providerType
            )
        } else {
            controls.webSearch?.enabled = isEnabled
            ChatControlNormalizationSupport.ensureValidWebSearchDefaultsIfEnabled(
                controls: &controls,
                providerType: providerType
            )
        }
        return controls
    }

    static func openAIWebSearchContextSizeValue(controls: GenerationControls) -> WebSearchContextSize {
        controls.webSearch?.contextSize ?? .medium
    }

    static func perplexityWebSearchContextSizeValue(controls: GenerationControls) -> WebSearchContextSize {
        controls.webSearch?.contextSize ?? .low
    }

    static func xaiWebSearchSourcesAreEmpty(controls: GenerationControls) -> Bool {
        Set(controls.webSearch?.sources ?? []).isEmpty
    }

    static func setExistingWebSearchContextSize(
        _ size: WebSearchContextSize,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.webSearch?.contextSize = size
        return controls
    }

    static func setPerplexityWebSearchContextSize(
        _ size: WebSearchContextSize,
        controls: GenerationControls,
        providerType: ProviderType?
    ) -> GenerationControls {
        var controls = controls
        if controls.webSearch == nil {
            controls.webSearch = ChatControlNormalizationSupport.defaultWebSearchControls(
                enabled: true,
                providerType: providerType
            )
        }
        controls.webSearch?.contextSize = size
        return controls
    }

    static func setWebSearchSource(
        _ source: WebSearchSource,
        isOn: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        var sources = Set(controls.webSearch?.sources ?? [])
        if isOn {
            sources.insert(source)
        } else {
            sources.remove(source)
        }
        controls.webSearch?.sources = Array(sources).sorted { $0.rawValue < $1.rawValue }
        return controls
    }
}
