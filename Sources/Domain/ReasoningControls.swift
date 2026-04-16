import Foundation

/// Reasoning controls (unified for OpenAI effort and Anthropic budget).
struct ReasoningControls: Codable, Equatable {
    var enabled: Bool
    var effort: ReasoningEffort?
    var budgetTokens: Int?
    var anthropicThinkingDisplay: AnthropicThinkingDisplay?
    var summary: ReasoningSummary?

    init(
        enabled: Bool = true,
        effort: ReasoningEffort? = nil,
        budgetTokens: Int? = nil,
        anthropicThinkingDisplay: AnthropicThinkingDisplay? = nil,
        summary: ReasoningSummary? = nil
    ) {
        self.enabled = enabled
        self.effort = effort
        self.budgetTokens = budgetTokens
        self.anthropicThinkingDisplay = anthropicThinkingDisplay
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
    case max

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extreme"
        case .max: return "Max"
        }
    }

    var anthropicDisplayName: String {
        switch self {
        case .xhigh:
            return "X-High"
        case .max:
            return "Max"
        default:
            return displayName
        }
    }
}

enum AnthropicThinkingDisplay: String, Codable, CaseIterable {
    case summarized
    case omitted

    var displayName: String {
        switch self {
        case .summarized:
            return "Summarized"
        case .omitted:
            return "Omitted"
        }
    }
}

/// Reasoning summary detail levels (OpenAI).
enum ReasoningSummary: String, Codable, CaseIterable {
    case auto
    case concise
    case detailed
    case none

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .auto, .concise, .detailed:
            return rawValue.capitalized
        }
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
