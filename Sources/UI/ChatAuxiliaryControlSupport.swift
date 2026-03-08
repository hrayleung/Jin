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

enum ChatAuxiliaryControlSupport {
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
        servers: [MCPServerConfigEntity]
    ) throws -> [MCPServerConfig] {
        guard supportsMCPToolsControl else { return [] }
        guard controls.mcpTools?.enabled == true else { return [] }

        let eligibleServers = eligibleMCPServers(from: servers)
        let eligibleIDs = Set(eligibleServers.map(\.id))
        let allowlist = controls.mcpTools?.enabledServerIDs
        let selectedIDs = allowlist.map(Set.init) ?? eligibleIDs
        let resolvedIDs = selectedIDs.intersection(eligibleIDs)

        return try eligibleServers
            .filter { resolvedIDs.contains($0.id) }
            .map { try $0.toConfig() }
    }
}
