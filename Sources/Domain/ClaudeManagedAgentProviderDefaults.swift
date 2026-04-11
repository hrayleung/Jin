import Foundation

private enum ClaudeManagedAgentProviderDefaultsKey {
    static let defaultAgentID = "claude_managed_default_agent_id"
    static let defaultEnvironmentID = "claude_managed_default_environment_id"
    static let defaultAgentDisplayName = "claude_managed_default_agent_display_name"
    static let defaultEnvironmentDisplayName = "claude_managed_default_environment_display_name"
    static let defaultAgentModelID = "claude_managed_default_agent_model_id"
    static let defaultAgentModelDisplayName = "claude_managed_default_agent_model_display_name"
}

extension ProviderConfig {
    var claudeManagedDefaultAgentID: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentID) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentID) }
    }

    var claudeManagedDefaultEnvironmentID: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentID) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentID) }
    }

    var claudeManagedDefaultAgentDisplayName: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentDisplayName) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentDisplayName) }
    }

    var claudeManagedDefaultEnvironmentDisplayName: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentDisplayName) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentDisplayName) }
    }

    var claudeManagedDefaultAgentModelID: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelID) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelID) }
    }

    var claudeManagedDefaultAgentModelDisplayName: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelDisplayName) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelDisplayName) }
    }

    mutating func normalizeClaudeManagedAgentDefaults() {
        let normalized = ClaudeManagedAgentRuntime.normalizedDescriptor(
            agentID: claudeManagedDefaultAgentID,
            environmentID: claudeManagedDefaultEnvironmentID,
            agentName: claudeManagedDefaultAgentDisplayName,
            environmentName: claudeManagedDefaultEnvironmentDisplayName,
            agentModelID: claudeManagedDefaultAgentModelID,
            agentModelDisplayName: claudeManagedDefaultAgentModelDisplayName
        )

        claudeManagedDefaultAgentID = normalized.agentID
        claudeManagedDefaultEnvironmentID = normalized.environmentID
        claudeManagedDefaultAgentDisplayName = normalized.agentName
        claudeManagedDefaultEnvironmentDisplayName = normalized.environmentName
        claudeManagedDefaultAgentModelID = normalized.agentModelID
        claudeManagedDefaultAgentModelDisplayName = normalized.agentModelDisplayName
    }

    private func authModeHintValue(for key: String) -> String? {
        guard let raw = authModeHintMap[key] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private mutating func setAuthModeHintValue(_ value: String?, for key: String) {
        var updated = authModeHintMap
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            updated[key] = trimmed
        } else {
            updated.removeValue(forKey: key)
        }
        authModeHint = ProviderConfigAuthHintCodec.encode(updated)
    }

    private var authModeHintMap: [String: String] {
        ProviderConfigAuthHintCodec.decode(authModeHint)
    }
}

extension ProviderConfigEntity {
    var claudeManagedDefaultAgentID: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentID) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentID) }
    }

    var claudeManagedDefaultEnvironmentID: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentID) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentID) }
    }

    var claudeManagedDefaultAgentDisplayName: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentDisplayName) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentDisplayName) }
    }

    var claudeManagedDefaultEnvironmentDisplayName: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentDisplayName) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultEnvironmentDisplayName) }
    }

    var claudeManagedDefaultAgentModelID: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelID) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelID) }
    }

    var claudeManagedDefaultAgentModelDisplayName: String? {
        get { authModeHintValue(for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelDisplayName) }
        set { setAuthModeHintValue(newValue, for: ClaudeManagedAgentProviderDefaultsKey.defaultAgentModelDisplayName) }
    }

    func applyClaudeManagedDefaults(into controls: inout GenerationControls) {
        guard ProviderType(rawValue: typeRaw) == .claudeManagedAgents else { return }

        let normalized = ClaudeManagedAgentRuntime.normalizedDescriptor(
            agentID: claudeManagedDefaultAgentID,
            environmentID: claudeManagedDefaultEnvironmentID,
            agentName: claudeManagedDefaultAgentDisplayName,
            environmentName: claudeManagedDefaultEnvironmentDisplayName,
            agentModelID: claudeManagedDefaultAgentModelID,
            agentModelDisplayName: claudeManagedDefaultAgentModelDisplayName
        )

        if controls.claudeManagedAgentID == nil {
            controls.claudeManagedAgentID = normalized.agentID
        }
        if controls.claudeManagedEnvironmentID == nil {
            controls.claudeManagedEnvironmentID = normalized.environmentID
        }
        if controls.claudeManagedAgentDisplayName == nil {
            controls.claudeManagedAgentDisplayName = normalized.agentName
        }
        if controls.claudeManagedEnvironmentDisplayName == nil {
            controls.claudeManagedEnvironmentDisplayName = normalized.environmentName
        }
        if controls.claudeManagedAgentModelID == nil {
            controls.claudeManagedAgentModelID = normalized.agentModelID
        }
        if controls.claudeManagedAgentModelDisplayName == nil {
            controls.claudeManagedAgentModelDisplayName = normalized.agentModelDisplayName
        }
    }

    private func authModeHintValue(for key: String) -> String? {
        guard let raw = ProviderConfigAuthHintCodec.decode(apiKeyKeychainID)[key] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setAuthModeHintValue(_ value: String?, for key: String) {
        var updated = ProviderConfigAuthHintCodec.decode(apiKeyKeychainID)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            updated[key] = trimmed
        } else {
            updated.removeValue(forKey: key)
        }
        apiKeyKeychainID = ProviderConfigAuthHintCodec.encode(updated)
    }
}

private enum ProviderConfigAuthHintCodec {
    static func decode(_ raw: String?) -> [String: String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return [:]
        }
        guard raw.hasPrefix("{"),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ["legacy": raw]
        }
        return decoded
    }

    static func encode(_ values: [String: String]) -> String? {
        let filtered = values.compactMapValues { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !filtered.isEmpty,
              let data = try? JSONEncoder().encode(filtered),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
