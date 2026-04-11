import Foundation

private enum ClaudeManagedAgentProviderSpecificKey {
    static let agentID = "claude_managed_agent_id"
    static let environmentID = "claude_managed_environment_id"
    static let agentDisplayName = "claude_managed_agent_display_name"
    static let environmentDisplayName = "claude_managed_environment_display_name"
    static let agentModelID = "claude_managed_agent_model_id"
    static let agentModelDisplayName = "claude_managed_agent_model_display_name"
    static let sessionID = "claude_managed_internal_session_id"
    static let sessionModelID = "claude_managed_internal_session_model_id"
    static let pendingCustomToolResults = "claude_managed_internal_pending_custom_tool_results"
}

struct ClaudeManagedAgentPendingToolResult: Codable, Equatable, Sendable {
    let eventID: String
    let toolCallID: String
    let toolName: String
    let content: String
    let isError: Bool
    let sessionThreadID: String?
}

extension GenerationControls {
    var claudeManagedAgentID: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.agentID) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.agentID) }
    }

    var claudeManagedEnvironmentID: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.environmentID) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.environmentID) }
    }

    var claudeManagedAgentDisplayName: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.agentDisplayName) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.agentDisplayName) }
    }

    var claudeManagedEnvironmentDisplayName: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.environmentDisplayName) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.environmentDisplayName) }
    }

    var claudeManagedAgentModelID: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.agentModelID) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.agentModelID) }
    }

    var claudeManagedAgentModelDisplayName: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.agentModelDisplayName) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.agentModelDisplayName) }
    }

    var claudeManagedSessionID: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.sessionID) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.sessionID) }
    }

    var claudeManagedSessionModelID: String? {
        get { normalizedClaudeManagedAgentString(for: ClaudeManagedAgentProviderSpecificKey.sessionModelID) }
        set { setClaudeManagedAgentString(newValue, for: ClaudeManagedAgentProviderSpecificKey.sessionModelID) }
    }

    var claudeManagedPendingCustomToolResults: [ClaudeManagedAgentPendingToolResult] {
        get {
            guard let raw = providerSpecific[ClaudeManagedAgentProviderSpecificKey.pendingCustomToolResults]?.value else {
                return []
            }

            if let data = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode([ClaudeManagedAgentPendingToolResult].self, from: data) {
                return decoded
            }

            return []
        }
        set {
            if newValue.isEmpty {
                providerSpecific.removeValue(forKey: ClaudeManagedAgentProviderSpecificKey.pendingCustomToolResults)
            } else {
                providerSpecific[ClaudeManagedAgentProviderSpecificKey.pendingCustomToolResults] = AnyCodable(
                    newValue.map { result in
                        [
                            "eventID": result.eventID,
                            "toolCallID": result.toolCallID,
                            "toolName": result.toolName,
                            "content": result.content,
                            "isError": result.isError,
                            "sessionThreadID": result.sessionThreadID as Any
                        ]
                    }
                )
            }
        }
    }

    var claudeManagedSessionOverrideCount: Int {
        var count = 0
        if claudeManagedAgentID != nil { count += 1 }
        if claudeManagedEnvironmentID != nil { count += 1 }
        return count
    }

    mutating func normalizeClaudeManagedAgentProviderSpecific(for providerType: ProviderType?) {
        guard providerType == .claudeManagedAgents else {
            removeClaudeManagedAgentProviderSpecificKeys()
            return
        }

        claudeManagedAgentID = claudeManagedAgentID
        claudeManagedEnvironmentID = claudeManagedEnvironmentID
        claudeManagedAgentDisplayName = claudeManagedAgentDisplayName
        claudeManagedEnvironmentDisplayName = claudeManagedEnvironmentDisplayName
        claudeManagedAgentModelID = claudeManagedAgentModelID
        claudeManagedAgentModelDisplayName = claudeManagedAgentModelDisplayName
        claudeManagedSessionID = claudeManagedSessionID
        claudeManagedSessionModelID = claudeManagedSessionModelID
        claudeManagedPendingCustomToolResults = claudeManagedPendingCustomToolResults
    }

    mutating func removeClaudeManagedAgentProviderSpecificKeys() {
        let managedKeys = providerSpecific.keys.filter { $0.hasPrefix("claude_managed_") }
        for key in managedKeys {
            providerSpecific.removeValue(forKey: key)
        }
    }

    mutating func clearClaudeManagedAgentSessionState() {
        claudeManagedSessionID = nil
        claudeManagedSessionModelID = nil
        claudeManagedPendingCustomToolResults = []
    }

    private func normalizedClaudeManagedAgentString(for key: String) -> String? {
        guard let raw = providerSpecific[key]?.value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private mutating func setClaudeManagedAgentString(_ value: String?, for key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            providerSpecific[key] = AnyCodable(trimmed)
        } else {
            providerSpecific.removeValue(forKey: key)
        }
    }
}
