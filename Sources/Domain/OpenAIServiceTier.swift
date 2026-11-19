import Foundation

/// OpenAI Responses/Chat Completions `service_tier` request values.
///
/// Docs:
/// - `default`: force standard tier processing
/// - `flex`: use flex processing
/// - `priority`: use priority processing
/// - `ultrafast`: use the highest-speed tier on eligible models
/// - `scale`: use scale tier processing (if enabled on the project)
///
/// `auto` is represented by `nil` in `GenerationControls.openAIServiceTier`
/// so requests can rely on OpenAI's default behavior when unset.
enum OpenAIServiceTier: String, Codable, CaseIterable {
    case defaultTier = "default"
    case flex
    case priority
    case ultrafast
    case scale

    var displayName: String {
        switch self {
        case .defaultTier:
            return "Default"
        case .flex:
            return "Flex"
        case .priority:
            return "Priority"
        case .ultrafast:
            return "Ultrafast"
        case .scale:
            return "Scale"
        }
    }

    var badgeText: String {
        switch self {
        case .defaultTier:
            return "D"
        case .flex:
            return "F"
        case .priority:
            return "P"
        case .ultrafast:
            return "U"
        case .scale:
            return "S"
        }
    }

    static func available(for modelID: String?, providerType: ProviderType?) -> [OpenAIServiceTier] {
        switch providerType {
        case .openai, .openaiWebSocket:
            if let modelID, OpenAIModelSupport.isGPT62(modelID) {
                return [.defaultTier, .priority, .ultrafast]
            }
            return allCases.filter { $0 != .ultrafast || supportsUltrafast(modelID: modelID, providerType: providerType) }
        case .vercelAIGateway:
            return supportsUltrafast(modelID: modelID, providerType: providerType) ? [.ultrafast] : []
        default:
            return []
        }
    }

    static func selected(
        in controls: GenerationControls,
        modelID: String?,
        providerType: ProviderType?
    ) -> OpenAIServiceTier? {
        let legacy = controls.providerSpecific["service_tier"]?.value as? String
        guard let tier = controls.openAIServiceTier ?? normalized(rawValue: legacy),
              available(for: modelID, providerType: providerType).contains(tier) else {
            return nil
        }
        return tier
    }

    static func normalized(rawValue: String?) -> OpenAIServiceTier? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmedLowercased
        guard !normalized.isEmpty else { return nil }
        guard normalized != "auto" else { return nil }
        return OpenAIServiceTier(rawValue: normalized)
    }

    static func supportsUltrafast(modelID: String?, providerType: ProviderType?) -> Bool {
        guard let modelID else { return false }
        let lower = modelID.lowercased()
        switch providerType {
        case .openai, .openaiWebSocket:
            return ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-astra", "gpt-6.1-sol"].contains(lower)
        case .vercelAIGateway:
            return ["openai/gpt-6.2-astra", "openai/gpt-6.2-sol"].contains(lower)
        default:
            return false
        }
    }
}
