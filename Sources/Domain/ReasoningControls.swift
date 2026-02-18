import Foundation

/// Reasoning controls (unified for OpenAI effort and Anthropic budget).
struct ReasoningControls: Codable, Equatable {
    var enabled: Bool
    var effort: ReasoningEffort?
    var budgetTokens: Int?
    var summary: ReasoningSummary?

    init(
        enabled: Bool = true,
        effort: ReasoningEffort? = nil,
        budgetTokens: Int? = nil,
        summary: ReasoningSummary? = nil
    ) {
        self.enabled = enabled
        self.effort = effort
        self.budgetTokens = budgetTokens
        self.summary = summary
    }
}

/// Reasoning effort levels (OpenAI, Vertex Gemini 3).
enum ReasoningEffort: String, Codable, CaseIterable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extreme"
        }
    }
}

/// Reasoning summary detail levels (OpenAI).
enum ReasoningSummary: String, Codable, CaseIterable {
    case auto
    case concise
    case detailed

    var displayName: String {
        rawValue.capitalized
    }
}

/// Model reasoning configuration.
struct ModelReasoningConfig: Codable, Equatable {
    let type: ReasoningConfigType
    let defaultEffort: ReasoningEffort?
    let defaultBudget: Int?

    init(
        type: ReasoningConfigType,
        defaultEffort: ReasoningEffort? = nil,
        defaultBudget: Int? = nil
    ) {
        self.type = type
        self.defaultEffort = defaultEffort
        self.defaultBudget = defaultBudget
    }
}

/// Reasoning configuration type.
enum ReasoningConfigType: String, Codable {
    case effort
    case budget
    case toggle
    case none
}
