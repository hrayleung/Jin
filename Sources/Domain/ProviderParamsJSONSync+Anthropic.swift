import Foundation

// MARK: - Anthropic Draft & Apply

extension ProviderParamsJSONSync {

    static func makeAnthropicDraft(controls: GenerationControls, modelID: String) -> [String: Any] {
        var out: [String: Any] = [:]

        if let temperature = controls.temperature {
            out["temperature"] = temperature
        }

        if let topP = controls.topP {
            out["top_p"] = topP
        }

        if let maxTokens = controls.maxTokens {
            out["max_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning, reasoning.enabled {
            let supportsAdaptive = AnthropicModelLimits.supportsAdaptiveThinking(for: modelID)
            let supportsEffort = AnthropicModelLimits.supportsEffort(for: modelID)

            if supportsAdaptive, reasoning.budgetTokens == nil {
                out["thinking"] = ["type": "adaptive"]
            } else {
                out["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": reasoning.budgetTokens ?? 2048
                ]
            }

            if supportsEffort, reasoning.budgetTokens == nil, let effort = reasoning.effort {
                out["output_config"] = [
                    "effort": mapAnthropicEffort(effort, modelID: modelID)
                ]
            }
        }

        if controls.webSearch?.enabled == true {
            let ws = controls.webSearch!
            let supportsDynamicFiltering = ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
                for: .anthropic,
                modelID: modelID
            )
            let useDynamicFiltering = (ws.dynamicFiltering == true) && supportsDynamicFiltering

            let allowedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(ws.allowedDomains)
            let blockedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(ws.blockedDomains)

            var spec: [String: Any] = [
                "type": useDynamicFiltering ? "web_search_20260209" : "web_search_20250305",
                "name": "web_search"
            ]
            if let maxUses = ws.maxUses, maxUses > 0 {
                spec["max_uses"] = maxUses
            }
            if !allowedDomains.isEmpty {
                spec["allowed_domains"] = allowedDomains
            } else if !blockedDomains.isEmpty {
                spec["blocked_domains"] = blockedDomains
            }
            if let loc = ws.userLocation, !loc.isEmpty {
                var locDict: [String: Any] = ["type": "approximate"]
                if let city = loc.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                    locDict["city"] = city
                }
                if let region = loc.region?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
                    locDict["region"] = region
                }
                if let country = loc.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
                    locDict["country"] = country
                }
                if let tz = loc.timezone?.trimmingCharacters(in: .whitespacesAndNewlines), !tz.isEmpty {
                    locDict["timezone"] = tz
                }
                spec["user_location"] = locDict
            }
            out["tools"] = [spec]
        }

        return out
    }

    static func applyAnthropic(
        draft: [String: AnyCodable],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        if let raw = draft["temperature"]?.value {
            if let value = doubleValue(from: raw) {
                controls.temperature = value
                providerSpecific.removeValue(forKey: "temperature")
            }
        } else {
            controls.temperature = nil
        }

        if let raw = draft["top_p"]?.value {
            if let value = doubleValue(from: raw) {
                controls.topP = value
                providerSpecific.removeValue(forKey: "top_p")
            }
        } else {
            controls.topP = nil
        }

        if let raw = draft["max_tokens"]?.value {
            if let value = intValue(from: raw) {
                controls.maxTokens = value
                providerSpecific.removeValue(forKey: "max_tokens")
            }
        } else {
            controls.maxTokens = nil
        }

        if let raw = draft["thinking"]?.value {
            if let dict = raw as? [String: Any] {
                let canPromote = applyAnthropicThinking(dict, modelID: modelID, controls: &controls)
                if canPromote {
                    providerSpecific.removeValue(forKey: "thinking")
                }
            }
        } else {
            controls.reasoning = nil
        }

        if let raw = draft["output_config"]?.value {
            if let dict = raw as? [String: Any] {
                applyAnthropicOutputConfig(dict, modelID: modelID, controls: &controls, providerSpecific: &providerSpecific)
            }
        }

        if let raw = draft["tools"]?.value {
            let canPromote = applyAnthropicWebSearchTools(raw, controls: &controls)
            if canPromote {
                providerSpecific.removeValue(forKey: "tools")
            }
        } else {
            controls.webSearch = nil
        }
    }

    // MARK: - Anthropic Helpers

    static func applyAnthropicThinking(_ dict: [String: Any], modelID: String, controls: inout GenerationControls) -> Bool {
        let knownKeys: Set<String> = ["type", "budget_tokens"]
        let isSimple = Set(dict.keys).isSubset(of: knownKeys)

        let typeRaw = dict["type"] as? String
        let type = typeRaw?.lowercased()
        let budgetTokens = dict["budget_tokens"].flatMap(intValue(from:))

        var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
        reasoning.enabled = true

        switch type {
        case "adaptive":
            reasoning.budgetTokens = nil
        case "enabled", nil:
            reasoning.budgetTokens = budgetTokens
        default:
            reasoning.budgetTokens = budgetTokens
        }

        if AnthropicModelLimits.supportsEffort(for: modelID), reasoning.budgetTokens != nil {
            reasoning.effort = nil
        }

        reasoning.summary = nil
        controls.reasoning = reasoning

        guard isSimple, typeRaw != nil else { return false }
        guard type == "adaptive" || type == "enabled" else { return false }
        if dict["budget_tokens"] != nil, budgetTokens == nil {
            return false
        }

        return true
    }

    static func applyAnthropicOutputConfig(
        _ dict: [String: Any],
        modelID: String,
        controls: inout GenerationControls,
        providerSpecific: inout [String: AnyCodable]
    ) {
        guard AnthropicModelLimits.supportsEffort(for: modelID) else { return }

        var remaining = dict
        if let effortString = dict["effort"] as? String,
           let effort = parseAnthropicEffort(effortString) {
            var reasoning = controls.reasoning ?? ReasoningControls(enabled: true)
            reasoning.enabled = true
            reasoning.effort = effort
            reasoning.budgetTokens = nil
            reasoning.summary = nil
            controls.reasoning = reasoning

            remaining.removeValue(forKey: "effort")
        }

        if remaining.isEmpty {
            providerSpecific.removeValue(forKey: "output_config")
        } else {
            providerSpecific["output_config"] = AnyCodable(remaining)
        }
    }

    static func applyAnthropicWebSearchTools(
        _ raw: Any,
        controls: inout GenerationControls
    ) -> Bool {
        guard let array = raw as? [Any] else { return false }

        let webSearchTypes: Set<String> = ["web_search_20250305", "web_search_20260209"]
        var found = false
        var nonSearchToolCount = 0
        var canPromoteToUI = (array.count == 1)

        let knownKeys: Set<String> = [
            "type", "name", "max_uses", "allowed_domains", "blocked_domains", "user_location"
        ]

        var parsedMaxUses: Int?
        var parsedAllowed: [String]?
        var parsedBlocked: [String]?
        var parsedLocation: WebSearchUserLocation?
        var parsedDynamicFiltering: Bool?

        for item in array {
            guard let dict = item as? [String: Any] else {
                nonSearchToolCount += 1
                canPromoteToUI = false
                continue
            }

            if let type = dict["type"] as? String, webSearchTypes.contains(type) {
                found = true

                if type == "web_search_20260209" {
                    parsedDynamicFiltering = true
                }

                if !Set(dict.keys).isSubset(of: knownKeys) {
                    canPromoteToUI = false
                }

                if let name = dict["name"] as? String, name != "web_search" {
                    canPromoteToUI = false
                }

                if let maxUses = dict["max_uses"] as? Int {
                    parsedMaxUses = maxUses
                }
                if let allowed = dict["allowed_domains"] as? [String] {
                    let normalizedAllowed = AnthropicWebSearchDomainUtils.normalizedDomains(allowed)
                    if !normalizedAllowed.isEmpty {
                        parsedAllowed = normalizedAllowed
                    }
                }
                if let blocked = dict["blocked_domains"] as? [String] {
                    let normalizedBlocked = AnthropicWebSearchDomainUtils.normalizedDomains(blocked)
                    if !normalizedBlocked.isEmpty {
                        parsedBlocked = normalizedBlocked
                    }
                }
                if let locDict = dict["user_location"] as? [String: Any] {
                    parsedLocation = WebSearchUserLocation(
                        city: locDict["city"] as? String,
                        region: locDict["region"] as? String,
                        country: locDict["country"] as? String,
                        timezone: locDict["timezone"] as? String
                    )
                }
            } else {
                nonSearchToolCount += 1
                canPromoteToUI = false
            }
        }

        if parsedAllowed != nil && parsedBlocked != nil {
            canPromoteToUI = false
            parsedBlocked = nil
        }

        controls.webSearch = found
            ? WebSearchControls(
                enabled: true,
                maxUses: parsedMaxUses,
                allowedDomains: parsedAllowed,
                blockedDomains: parsedBlocked,
                userLocation: parsedLocation,
                dynamicFiltering: parsedDynamicFiltering
            )
            : nil

        return found && nonSearchToolCount == 0 && canPromoteToUI
    }

    static func mapAnthropicEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        switch effort {
        case .none:
            return "high"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return AnthropicModelLimits.supportsMaxEffort(for: modelID) ? "max" : "high"
        }
    }

    static func parseAnthropicEffort(_ raw: String) -> ReasoningEffort? {
        switch raw.lowercased() {
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        case "max":
            return .xhigh
        default:
            return nil
        }
    }
}
