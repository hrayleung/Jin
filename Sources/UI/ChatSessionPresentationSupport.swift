import Foundation

extension ChatAuxiliaryControlSupport {
    static func openAIServiceTierHelpText(
        supportsOpenAIServiceTierControl: Bool,
        label: String
    ) -> String {
        guard supportsOpenAIServiceTierControl else { return "Service Tier: Not supported" }
        return "Service Tier: \(label)"
    }

    static func openAIServiceTierLabel(controls: GenerationControls) -> String {
        controls.openAIServiceTier?.displayName ?? "Auto"
    }

    static func openAIServiceTierBadgeText(
        supportsOpenAIServiceTierControl: Bool,
        controls: GenerationControls
    ) -> String? {
        guard supportsOpenAIServiceTierControl else { return nil }
        return controls.openAIServiceTier?.badgeText
    }

    static func anthropicFastModeHelpText(
        supportsAnthropicFastModeControl: Bool,
        controls: GenerationControls
    ) -> String {
        guard supportsAnthropicFastModeControl else { return "Fast Mode: Not supported" }
        let state = controls.anthropicSpeed == .fast ? "On" : "Off"
        return "Fast Mode (beta): \(state) \u{00B7} 2.5x faster output, $30/$150 MTok"
    }

    static func anthropicFastModeBadgeText(
        supportsAnthropicFastModeControl: Bool,
        controls: GenerationControls
    ) -> String? {
        guard supportsAnthropicFastModeControl else { return nil }
        return controls.anthropicSpeed?.badgeText
    }

    static func claudeManagedAgentSessionBadgeText(controls: GenerationControls) -> String? {
        guard controls.claudeManagedSessionOverrideCount > 0 else { return nil }
        if controls.claudeManagedAgentID != nil, controls.claudeManagedEnvironmentID != nil {
            return "2"
        }
        return "1"
    }

    static func claudeManagedAgentSessionHelpText(
        supportsClaudeManagedAgentSessionControl: Bool,
        resolvedControls: GenerationControls,
        agentDisplayName: String?,
        environmentDisplayName: String?
    ) -> String {
        guard supportsClaudeManagedAgentSessionControl else {
            return "Claude Managed Agent: Not supported"
        }

        return helpText(
            title: "Claude Managed Agent",
            segments: claudeManagedAgentSessionHelpSegments(
                resolvedControls: resolvedControls,
                agentDisplayName: agentDisplayName,
                environmentDisplayName: environmentDisplayName
            )
        )
    }

    private static func claudeManagedAgentSessionHelpSegments(
        resolvedControls: GenerationControls,
        agentDisplayName: String?,
        environmentDisplayName: String?
    ) -> [String] {
        var segments: [String] = []
        if resolvedControls.claudeManagedAgentID != nil {
            segments.append("Agent: \(agentDisplayName ?? "not configured")")
        } else {
            segments.append("Agent: not configured")
        }

        if resolvedControls.claudeManagedEnvironmentID != nil, let environmentDisplayName {
            segments.append("Environment: \(environmentDisplayName)")
        } else {
            segments.append("Environment: not configured")
        }

        if let sessionID = resolvedControls.claudeManagedSessionID {
            segments.append("Session: \(sessionID)")
        }

        return segments
    }

    private static func helpText(title: String, segments: [String]) -> String {
        "\(title): \(segments.joined(separator: " \u{00B7} "))"
    }
}
