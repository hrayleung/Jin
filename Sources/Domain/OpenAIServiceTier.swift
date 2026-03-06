import Foundation

/// OpenAI Responses/Chat Completions `service_tier` request values.
///
/// Docs:
/// - `default`: force standard tier processing
/// - `flex`: use flex processing
/// - `priority`: use priority processing
/// - `scale`: use scale tier processing (if enabled on the project)
///
/// `auto` is represented by `nil` in `GenerationControls.openAIServiceTier`
/// so requests can rely on OpenAI's default behavior when unset.
enum OpenAIServiceTier: String, Codable, CaseIterable {
    case defaultTier = "default"
    case flex
    case priority
    case scale

    var displayName: String {
        switch self {
        case .defaultTier:
            return "Default"
        case .flex:
            return "Flex"
        case .priority:
            return "Priority"
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
        case .scale:
            return "S"
        }
    }

    static func normalized(rawValue: String?) -> OpenAIServiceTier? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        guard normalized != "auto" else { return nil }
        return OpenAIServiceTier(rawValue: normalized)
    }
}
