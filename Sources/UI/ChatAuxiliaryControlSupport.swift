import Foundation
import SwiftUI

struct PreparedContextCacheEditorDraft {
    let draft: ContextCacheControls
    let ttlPreset: ContextCacheTTLPreset
    let customTTLDraft: String
    let minTokensDraft: String
    let advancedExpanded: Bool
}

struct PreparedAnthropicWebSearchEditorDraft {
    let domainMode: AnthropicDomainFilterMode
    let allowedDomainsDraft: String
    let blockedDomainsDraft: String
    let locationDraft: WebSearchUserLocation
}

struct PreparedGoogleMapsEditorDraft {
    let draft: GoogleMapsControls
    let latitudeDraft: String
    let longitudeDraft: String
    let languageCodeDraft: String
}

enum ChatAuxiliaryControlSupport {
    static func prepareGoogleMapsEditorDraft(
        current: GoogleMapsControls?,
        isEnabled: Bool
    ) -> PreparedGoogleMapsEditorDraft {
        let draft = current ?? GoogleMapsControls(enabled: isEnabled)
        return PreparedGoogleMapsEditorDraft(
            draft: draft,
            latitudeDraft: draft.latitude.map { String($0) } ?? "",
            longitudeDraft: draft.longitude.map { String($0) } ?? "",
            languageCodeDraft: draft.languageCode ?? ""
        )
    }

    static func isGoogleMapsDraftValid(
        latitudeDraft: String,
        longitudeDraft: String
    ) -> Bool {
        switch validatedGoogleMapsCoordinates(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        ) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    static func applyGoogleMapsDraft(
        draft: GoogleMapsControls,
        latitudeDraft: String,
        longitudeDraft: String,
        languageCodeDraft: String,
        providerType: ProviderType?
    ) -> Result<GoogleMapsControls?, ChatEditorDraftError> {
        var draft = draft

        switch validatedGoogleMapsCoordinates(
            latitudeDraft: latitudeDraft,
            longitudeDraft: longitudeDraft
        ) {
        case .success(let coordinates):
            draft.latitude = coordinates.latitude
            draft.longitude = coordinates.longitude
        case .failure(let error):
            return .failure(error)
        }

        let trimmedLanguage = languageCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if providerType == .vertexai, !trimmedLanguage.isEmpty {
            draft.languageCode = trimmedLanguage
        } else {
            draft.languageCode = nil
        }

        if draft.enableWidget != true {
            draft.enableWidget = nil
        }

        return .success(draft.isEmpty ? nil : draft)
    }

    static func prepareContextCacheEditorDraft(
        current: ContextCacheControls?,
        providerType: ProviderType?,
        supportsContextCacheTTL: Bool
    ) -> PreparedContextCacheEditorDraft {
        let defaultMode: ContextCacheMode = (providerType == .anthropic) ? .implicit : .off
        let draft = current ?? ContextCacheControls(mode: defaultMode)
        let ttlPreset = ContextCacheTTLPreset.from(ttl: draft.ttl)
        let customTTLDraft: String
        if case .customSeconds(let seconds) = draft.ttl {
            customTTLDraft = "\(seconds)"
        } else {
            customTTLDraft = ""
        }

        return PreparedContextCacheEditorDraft(
            draft: draft,
            ttlPreset: ttlPreset,
            customTTLDraft: customTTLDraft,
            minTokensDraft: draft.minTokensThreshold.map(String.init) ?? "",
            advancedExpanded: shouldExpandContextCacheAdvancedOptions(
                for: draft,
                providerType: providerType,
                supportsContextCacheTTL: supportsContextCacheTTL
            )
        )
    }

    static func shouldExpandContextCacheAdvancedOptions(
        for draft: ContextCacheControls,
        providerType: ProviderType?,
        supportsContextCacheTTL: Bool
    ) -> Bool {
        guard draft.mode != .off else { return false }

        if supportsContextCacheTTL,
           let ttl = draft.ttl,
           ttl != .providerDefault {
            return true
        }

        if providerType == .xai {
            if let cacheKey = draft.cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cacheKey.isEmpty {
                return true
            }
        }

        if providerType == .xai,
           let conversationID = draft.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationID.isEmpty {
            return true
        }

        return false
    }

    static func isContextCacheDraftValid(
        contextCacheDraft: ContextCacheControls,
        ttlPreset: ContextCacheTTLPreset,
        customTTLDraft: String,
        minTokensDraft: String,
        supportsExplicitContextCacheMode: Bool
    ) -> Bool {
        if ttlPreset == .custom {
            let trimmed = customTTLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed), value > 0 else { return false }
        }

        let minTokensTrimmed = minTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !minTokensTrimmed.isEmpty {
            guard let value = Int(minTokensTrimmed), value > 0 else { return false }
        }

        if supportsExplicitContextCacheMode, contextCacheDraft.mode == .explicit {
            let name = (contextCacheDraft.cachedContentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty
        }

        return true
    }

    static func applyContextCacheDraft(
        draft: ContextCacheControls,
        ttlPreset: ContextCacheTTLPreset,
        customTTLDraft: String,
        minTokensDraft: String,
        supportsContextCacheTTL: Bool,
        supportsContextCacheStrategy: Bool,
        supportsExplicitContextCacheMode: Bool,
        providerType: ProviderType?
    ) -> Result<ContextCacheControls?, ChatEditorDraftError> {
        var draft = draft

        if supportsContextCacheTTL {
            switch ttlPreset {
            case .providerDefault:
                draft.ttl = .providerDefault
            case .minutes5:
                draft.ttl = .minutes5
            case .hour1:
                draft.ttl = .hour1
            case .custom:
                let trimmed = customTTLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Int(trimmed), value > 0 else {
                    return .failure(.message("Custom TTL must be a positive integer (seconds)."))
                }
                draft.ttl = .customSeconds(value)
            }
        } else {
            draft.ttl = nil
        }

        let minTokensTrimmed = minTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if minTokensTrimmed.isEmpty {
            draft.minTokensThreshold = nil
        } else if let value = Int(minTokensTrimmed), value > 0 {
            draft.minTokensThreshold = value
        } else {
            return .failure(.message("Min tokens threshold must be a positive integer."))
        }

        draft.cacheKey = draft.cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.cacheKey?.isEmpty == true {
            draft.cacheKey = nil
        }

        draft.conversationID = draft.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.conversationID?.isEmpty == true {
            draft.conversationID = nil
        }

        draft.cachedContentName = draft.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.cachedContentName?.isEmpty == true {
            draft.cachedContentName = nil
        }

        if !supportsContextCacheStrategy {
            draft.strategy = nil
        } else if draft.strategy == nil {
            draft.strategy = .systemOnly
        }

        if !supportsExplicitContextCacheMode, draft.mode == .explicit {
            draft.mode = .implicit
        }

        if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
            draft.cacheKey = nil
        }
        if providerType != .xai {
            draft.minTokensThreshold = nil
        }
        if providerType != .xai {
            draft.conversationID = nil
        }
        if providerType != .gemini && providerType != .vertexai {
            draft.cachedContentName = nil
        }

        if draft.mode == .off {
            if providerType == .anthropic {
                return .success(ContextCacheControls(mode: .off))
            }
            return .success(nil)
        }

        return .success(draft)
    }

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

    private static func validatedGoogleMapsCoordinates(
        latitudeDraft: String,
        longitudeDraft: String
    ) -> Result<(latitude: Double?, longitude: Double?), ChatEditorDraftError> {
        let trimmedLatitude = latitudeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLongitude = longitudeDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLatitude.isEmpty && trimmedLongitude.isEmpty {
            return .success((nil, nil))
        }

        guard !trimmedLatitude.isEmpty, !trimmedLongitude.isEmpty else {
            return .failure(.message("Enter both latitude and longitude, or leave both empty."))
        }

        guard let latitude = Double(trimmedLatitude), (-90...90).contains(latitude) else {
            return .failure(.message("Latitude must be a number between -90 and 90."))
        }

        guard let longitude = Double(trimmedLongitude), (-180...180).contains(longitude) else {
            return .failure(.message("Longitude must be a number between -180 and 180."))
        }

        return .success((latitude, longitude))
    }

    static func eligibleMCPServers(
        from servers: [MCPServerConfigEntity]
    ) -> [MCPServerConfigEntity] {
        servers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func selectedMCPServerIDs(
        controls: GenerationControls,
        eligibleServers: [MCPServerConfigEntity]
    ) -> Set<String> {
        guard controls.mcpTools?.enabled == true else { return [] }
        let eligibleIDs = Set(eligibleServers.map(\.id))
        if let allowlist = controls.mcpTools?.enabledServerIDs {
            return Set(allowlist).intersection(eligibleIDs)
        }
        return eligibleIDs
    }

    static func toggleMCPServerSelection(
        controls: GenerationControls,
        eligibleServers: [MCPServerConfigEntity],
        serverID: String,
        isOn: Bool
    ) -> GenerationControls {
        var controls = controls
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        }

        let eligibleIDs = Set(eligibleServers.map(\.id))
        var selected = Set(controls.mcpTools?.enabledServerIDs ?? Array(eligibleIDs))
        if isOn {
            selected.insert(serverID)
        } else {
            selected.remove(serverID)
        }

        let normalized = selected.intersection(eligibleIDs)
        if normalized == eligibleIDs {
            controls.mcpTools?.enabledServerIDs = nil
        } else {
            controls.mcpTools?.enabledServerIDs = Array(normalized).sorted()
        }

        return controls
    }

    static func resetMCPServerSelection(controls: GenerationControls) -> GenerationControls {
        var controls = controls
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        } else {
            controls.mcpTools?.enabled = true
            controls.mcpTools?.enabledServerIDs = nil
        }
        return controls
    }

    static func resolvedMCPServerConfigs(
        controls: GenerationControls,
        supportsMCPToolsControl: Bool,
        servers: [MCPServerConfigEntity],
        perMessageOverrideServerIDs: Set<String> = []
    ) throws -> [MCPServerConfig] {
        guard supportsMCPToolsControl else { return [] }

        var effectiveControls = controls
        if !perMessageOverrideServerIDs.isEmpty {
            effectiveControls.mcpTools = MCPToolsControls(
                enabled: true,
                enabledServerIDs: Array(perMessageOverrideServerIDs).sorted()
            )
        }

        guard effectiveControls.mcpTools?.enabled == true else { return [] }

        let eligibleServers = eligibleMCPServers(from: servers)
        let eligibleIDs = Set(eligibleServers.map(\.id))
        let allowlist = effectiveControls.mcpTools?.enabledServerIDs
        let selectedIDs = allowlist.map(Set.init) ?? eligibleIDs
        let resolvedIDs = selectedIDs.intersection(eligibleIDs)

        return try eligibleServers
            .filter { resolvedIDs.contains($0.id) }
            .map { try $0.toConfig() }
    }

    // MARK: - Automatic Context Cache

    static func automaticContextCacheControls(
        providerType: ProviderType?,
        modelID: String,
        modelCapabilities: ModelCapability?,
        supportsMediaGenerationControl: Bool,
        conversationID: UUID
    ) -> ContextCacheControls? {
        guard !supportsMediaGenerationControl else { return nil }
        guard let providerType else { return nil }
        if providerType != .cloudflareAIGateway,
           let modelCapabilities,
           !modelCapabilities.contains(.promptCaching) {
            return nil
        }

        let cacheConversationID = automaticContextCacheConversationID(
            conversationID: conversationID,
            modelID: modelID
        )

        switch providerType {
        case .openai, .openaiWebSocket:
            return ContextCacheControls(mode: .implicit)
        case .xai:
            return ContextCacheControls(
                mode: .implicit,
                conversationID: cacheConversationID
            )
        case .anthropic:
            return ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .providerDefault
            )
        case .gemini, .vertexai:
            return ContextCacheControls(mode: .implicit)
        case .cloudflareAIGateway:
            return ContextCacheControls(mode: .implicit, ttl: .minutes5)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .vercelAIGateway, .openrouter, .perplexity, .groq, .cohere,
             .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .fireworks,
             .cerebras, .sambanova:
            return nil
        }
    }

    static func automaticContextCacheConversationID(conversationID: UUID, modelID: String) -> String {
        let conversationPart = conversationID.uuidString.lowercased()
        let modelPart = sanitizedContextCacheIdentifier(modelID, maxLength: 32)
        return "jin-conv-\(conversationPart)-\(modelPart)"
    }

    static func sanitizedContextCacheIdentifier(_ raw: String, maxLength: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let lower = raw.lowercased()
        var output = ""
        output.reserveCapacity(min(lower.count, maxLength))

        var previousWasHyphen = false
        for scalar in lower.unicodeScalars {
            guard output.count < maxLength else { break }
            let character = Character(scalar)
            if allowed.contains(character) {
                output.append(character)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                output.append("-")
                previousWasHyphen = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "model" : trimmed
    }
}
