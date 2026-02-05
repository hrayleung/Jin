import Foundation

enum AppPreferenceKeys {
    static let newChatModelMode = "newChatModelMode"
    static let newChatFixedProviderID = "newChatFixedProviderID"
    static let newChatFixedModelID = "newChatFixedModelID"

    static let newChatMCPMode = "newChatMCPMode"
    static let newChatFixedMCPEnabled = "newChatFixedMCPEnabled"
    static let newChatFixedMCPUseAllServers = "newChatFixedMCPUseAllServers"
    static let newChatFixedMCPServerIDsJSON = "newChatFixedMCPServerIDsJSON"
}

enum NewChatModelMode: String, CaseIterable, Identifiable {
    case fixed
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Use Specific Model"
        case .lastUsed: return "Use Last Used Model"
        }
    }
}

enum NewChatMCPMode: String, CaseIterable, Identifiable {
    case fixed
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Use Custom Defaults"
        case .lastUsed: return "Use Last Chat's MCP"
        }
    }
}

enum AppPreferences {
    static func decodeStringArrayJSON(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func encodeStringArrayJSON(_ value: [String]) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

