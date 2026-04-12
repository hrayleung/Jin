import Foundation

struct ClaudeManagedAgentDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let modelID: String?
    let modelDisplayName: String?

    init(
        id: String,
        name: String,
        modelID: String? = nil,
        modelDisplayName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
    }
}

struct ClaudeManagedEnvironmentDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

enum ClaudeManagedAgentRuntime {
    private static let syntheticModelPrefix = "claude-managed"

    static func syntheticThreadModelID(
        providerID: String,
        agentID: String?,
        environmentID: String?
    ) -> String {
        let normalizedAgentID = normalizedComponent(agentID) ?? "agent"
        let normalizedEnvironmentID = normalizedComponent(environmentID) ?? "env"
        return "\(syntheticModelPrefix)::\(providerID)::\(normalizedAgentID)::\(normalizedEnvironmentID)"
    }

    static func isSyntheticThreadModelID(_ modelID: String) -> Bool {
        modelID.hasPrefix("\(syntheticModelPrefix)::")
    }

    static func syntheticThreadDescriptor(
        modelID: String,
        providerID: String
    ) -> (agentID: String?, environmentID: String?)? {
        let components = modelID.components(separatedBy: "::")
        guard components.count == 4,
              components[0] == syntheticModelPrefix,
              components[1] == providerID else {
            return nil
        }

        return (
            decodeSyntheticComponent(components[2], placeholder: "agent"),
            decodeSyntheticComponent(components[3], placeholder: "env")
        )
    }

    static func resolvedRuntimeModelID(
        threadModelID: String,
        controls: GenerationControls
    ) -> String {
        if let remoteModelID = normalizedComponent(controls.claudeManagedSessionModelID) {
            return remoteModelID
        }
        if let remoteModelID = normalizedComponent(controls.claudeManagedAgentModelID) {
            return remoteModelID
        }
        if isSyntheticThreadModelID(threadModelID) {
            return "claude-sonnet-4-6"
        }
        return threadModelID
    }

    static func resolvedDisplayName(
        threadModelID: String,
        controls: GenerationControls
    ) -> String {
        if let name = normalizedComponent(controls.claudeManagedAgentDisplayName) {
            return name
        }
        if let id = normalizedComponent(controls.claudeManagedAgentID) {
            return id
        }
        if let name = normalizedComponent(controls.claudeManagedAgentModelDisplayName) {
            return name
        }
        if isSyntheticThreadModelID(threadModelID) {
            return "Managed Agent"
        }
        return threadModelID
    }

    static func normalizedDescriptor(
        agentID: String?,
        environmentID: String?,
        agentName: String?,
        environmentName: String?,
        agentModelID: String? = nil,
        agentModelDisplayName: String? = nil
    ) -> (
        agentID: String?,
        environmentID: String?,
        agentName: String?,
        environmentName: String?,
        agentModelID: String?,
        agentModelDisplayName: String?
    ) {
        (
            normalizedComponent(agentID),
            normalizedComponent(environmentID),
            normalizedComponent(agentName),
            normalizedComponent(environmentName),
            normalizedComponent(agentModelID),
            normalizedComponent(agentModelDisplayName)
        )
    }

    private static func normalizedComponent(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func decodeSyntheticComponent(
        _ value: String,
        placeholder: String
    ) -> String? {
        let normalized = normalizedComponent(value)
        guard normalized != placeholder else { return nil }
        return normalized
    }
}
