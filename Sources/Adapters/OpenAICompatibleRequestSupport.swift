import Foundation

enum OpenAICompatibleRequestSupport {
    static func applySamplingControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        shouldOmitSamplingControls: Bool
    ) {
        guard !shouldOmitSamplingControls else { return }
        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
    }

    static func applyMaxTokens(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType
    ) {
        guard let maxTokens = controls.maxTokens else { return }
        body[providerType == .mimoTokenPlanOpenAI ? "max_completion_tokens" : "max_tokens"] = maxTokens
    }

    static func applyOpenAIServiceTier(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType
    ) {
        guard providerType == .openai,
              let serviceTier = resolvedOpenAIServiceTier(from: controls) else {
            return
        }
        body["service_tier"] = serviceTier
    }

    static func miMoToolObjects(
        webSearch: WebSearchControls?,
        supportsNativeWebSearch: Bool,
        functionTools: [[String: Any]]
    ) -> [[String: Any]] {
        var toolObjects: [[String: Any]] = []
        if webSearch?.enabled == true, supportsNativeWebSearch {
            toolObjects.append(miMoWebSearchTool(from: webSearch))
        }
        toolObjects.append(contentsOf: functionTools)
        return toolObjects
    }

    static func miMoWebSearchTool(from controls: WebSearchControls?) -> [String: Any] {
        var tool: [String: Any] = ["type": "web_search"]

        if let limit = controls?.maxUses, limit > 0 {
            tool["limit"] = limit
            tool["max_keyword"] = limit
        }

        if let location = controls?.userLocation,
           let userLocation = miMoUserLocation(location) {
            tool["user_location"] = userLocation
        }

        return tool
    }

    static func applyProviderSpecificOverrides(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerConfig: ProviderConfig,
        modelID: String
    ) {
        for (key, value) in controls.providerSpecific {
            if providerConfig.type == .openai, key == "service_tier" {
                continue
            }

            if key == "chat_template_kwargs",
               OpenAICompatibleReasoningSupport.isCloudflareKimiK26Model(
                   providerConfig: providerConfig,
                   modelID: modelID
               ),
               let templateKwargs = value.value as? [String: Any] {
                OpenAICompatibleReasoningSupport.mergeChatTemplateKwargs(
                    into: &body,
                    additional: templateKwargs
                )
                continue
            }

            body[key] = value.value
        }
    }

    private static func miMoUserLocation(_ location: WebSearchUserLocation) -> [String: Any]? {
        var userLocation: [String: Any] = ["type": "approximate"]

        if let country = normalizedWebSearchLocationField(location.country) {
            userLocation["country"] = country
        }
        if let region = normalizedWebSearchLocationField(location.region) {
            userLocation["region"] = region
        }
        if let city = normalizedWebSearchLocationField(location.city) {
            userLocation["city"] = city
        }
        if let timezone = normalizedWebSearchLocationField(location.timezone) {
            userLocation["timezone"] = timezone
        }

        return userLocation.count > 1 ? userLocation : nil
    }

    private static func normalizedWebSearchLocationField(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }
}
