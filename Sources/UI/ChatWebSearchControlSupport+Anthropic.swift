import Foundation

struct PreparedAnthropicWebSearchEditorDraft {
    let domainMode: AnthropicDomainFilterMode
    let allowedDomainsDraft: String
    let blockedDomainsDraft: String
    let locationDraft: WebSearchUserLocation
}

extension ChatAuxiliaryControlSupport {
    static func prepareAnthropicWebSearchEditorDraft(
        webSearch: WebSearchControls?,
        currentMode: AnthropicDomainFilterMode
    ) -> PreparedAnthropicWebSearchEditorDraft {
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(webSearch?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(webSearch?.blockedDomains)

        let mode: AnthropicDomainFilterMode
        if currentMode == .blocked, !blocked.isEmpty {
            mode = .blocked
        } else if !allowed.isEmpty {
            mode = .allowed
        } else if !blocked.isEmpty {
            mode = .blocked
        } else {
            mode = .none
        }

        return PreparedAnthropicWebSearchEditorDraft(
            domainMode: mode,
            allowedDomainsDraft: allowed.joined(separator: "\n"),
            blockedDomainsDraft: blocked.joined(separator: "\n"),
            locationDraft: webSearch?.userLocation ?? WebSearchUserLocation()
        )
    }

    static func applyAnthropicWebSearchDraft(
        domainMode: AnthropicDomainFilterMode,
        allowedDomainsDraft: String,
        blockedDomainsDraft: String,
        locationDraft: WebSearchUserLocation,
        controls: GenerationControls
    ) -> Result<GenerationControls, ChatEditorDraftError> {
        var controls = controls
        let allowedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicWebSearchDomainUtils.splitInput(allowedDomainsDraft)
        )
        let blockedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicWebSearchDomainUtils.splitInput(blockedDomainsDraft)
        )

        switch domainMode {
        case .none:
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        case .allowed:
            if allowedDomains.isEmpty {
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = nil
            } else {
                if let validationError = AnthropicWebSearchDomainUtils.firstValidationError(in: allowedDomains) {
                    return .failure(.message(validationError))
                }
                controls.webSearch?.allowedDomains = allowedDomains
                controls.webSearch?.blockedDomains = nil
            }
        case .blocked:
            if blockedDomains.isEmpty {
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = nil
            } else {
                if let validationError = AnthropicWebSearchDomainUtils.firstValidationError(in: blockedDomains) {
                    return .failure(.message(validationError))
                }
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = blockedDomains
            }
        }

        ChatControlNormalizationSupport.normalizeAnthropicDomainFilters(controls: &controls)
        controls.webSearch?.userLocation = locationDraft.isEmpty ? nil : locationDraft
        return .success(controls)
    }

    static func setAnthropicDynamicFiltering(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.webSearch?.dynamicFiltering = isEnabled ? true : nil
        return controls
    }

    static func anthropicDynamicFilteringValue(controls: GenerationControls) -> Bool {
        controls.webSearch?.dynamicFiltering ?? false
    }

    static func anthropicWebSearchMaxUsesValue(controls: GenerationControls) -> Int? {
        controls.webSearch?.maxUses
    }

    static func setAnthropicWebSearchMaxUses(
        _ maxUses: Int?,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        controls.webSearch?.maxUses = maxUses
        return controls
    }
}
