import Foundation

enum AnthropicToolSpecSupport {
    static func customToolSpecs(from tools: [ToolDefinition]) -> [[String: Any]] {
        tools.map(customToolSpec)
    }

    static func codeExecutionToolSpec() -> [String: Any] {
        [
            "type": "code_execution_20250825",
            "name": "code_execution"
        ]
    }

    static func webSearchToolSpec(
        from controls: WebSearchControls,
        supportsDynamicFiltering: Bool
    ) -> [String: Any] {
        let useDynamicFiltering = (controls.dynamicFiltering == true) && supportsDynamicFiltering
        let allowedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(controls.allowedDomains)
        let blockedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(controls.blockedDomains)

        var spec: [String: Any] = [
            "type": useDynamicFiltering ? "web_search_20260209" : "web_search_20250305",
            "name": "web_search"
        ]
        if let maxUses = controls.maxUses, maxUses > 0 {
            spec["max_uses"] = maxUses
        }
        if !allowedDomains.isEmpty {
            spec["allowed_domains"] = allowedDomains
        } else if !blockedDomains.isEmpty {
            spec["blocked_domains"] = blockedDomains
        }
        if let location = controls.userLocation, !location.isEmpty {
            spec["user_location"] = userLocationDictionary(location)
        }
        return spec
    }

    static func normalizedProviderSpecificTools(
        _ value: Any,
        supportsDynamicFiltering: Bool
    ) -> Any {
        guard let tools = value as? [Any] else { return value }

        var normalized: [Any] = []
        normalized.reserveCapacity(tools.count)

        for item in tools {
            guard var dict = item as? [String: Any],
                  let type = dict["type"] as? String else {
                normalized.append(item)
                continue
            }

            if type == "web_search_20250305" || type == "web_search_20260209" {
                dict = normalizedWebSearchTool(dict, requestedType: type, supportsDynamicFiltering: supportsDynamicFiltering)
            }

            normalized.append(dict)
        }

        return normalized
    }

    private static func customToolSpec(_ tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "input_schema": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }

    private static func normalizedWebSearchTool(
        _ tool: [String: Any],
        requestedType: String,
        supportsDynamicFiltering: Bool
    ) -> [String: Any] {
        var dict = tool
        let useDynamicFiltering = (requestedType == "web_search_20260209") && supportsDynamicFiltering
        dict["type"] = useDynamicFiltering ? "web_search_20260209" : "web_search_20250305"

        if let maxUses = dict["max_uses"] as? Int, maxUses <= 0 {
            dict.removeValue(forKey: "max_uses")
        }

        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicRequestPreparationSupport.providerSpecificStringArray(dict["allowed_domains"] as Any)
        )
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicRequestPreparationSupport.providerSpecificStringArray(dict["blocked_domains"] as Any)
        )

        if !allowed.isEmpty {
            dict["allowed_domains"] = allowed
            dict.removeValue(forKey: "blocked_domains")
        } else if !blocked.isEmpty {
            dict["blocked_domains"] = blocked
            dict.removeValue(forKey: "allowed_domains")
        } else {
            dict.removeValue(forKey: "allowed_domains")
            dict.removeValue(forKey: "blocked_domains")
        }

        return dict
    }

    private static func userLocationDictionary(_ location: WebSearchUserLocation) -> [String: Any] {
        var locationDict: [String: Any] = ["type": "approximate"]
        if let city = normalizedTrimmedString(location.city) {
            locationDict["city"] = city
        }
        if let region = normalizedTrimmedString(location.region) {
            locationDict["region"] = region
        }
        if let country = normalizedTrimmedString(location.country) {
            locationDict["country"] = country
        }
        if let timezone = normalizedTrimmedString(location.timezone) {
            locationDict["timezone"] = timezone
        }
        return locationDict
    }
}
