import Foundation

/// Reasoning controls (unified for OpenAI effort and Anthropic budget).
struct ReasoningControls: Codable, Equatable {
    var enabled: Bool
    var effort: ReasoningEffort?
    var budgetTokens: Int?
    var anthropicThinkingDisplay: AnthropicThinkingDisplay?
    var summary: ReasoningSummary?
    /// OpenAI Responses API `reasoning.mode` (`pro` for GPT-5.6 quality mode).
    var mode: ReasoningMode?
    /// OpenAI Responses API `reasoning.context` for multi-turn reasoning reuse.
    var context: ReasoningContextMode?

    init(
        enabled: Bool = true,
        effort: ReasoningEffort? = nil,
        budgetTokens: Int? = nil,
        anthropicThinkingDisplay: AnthropicThinkingDisplay? = nil,
        summary: ReasoningSummary? = nil,
        mode: ReasoningMode? = nil,
        context: ReasoningContextMode? = nil
    ) {
        self.enabled = enabled
        self.effort = effort
        self.budgetTokens = budgetTokens
        self.anthropicThinkingDisplay = anthropicThinkingDisplay
        self.summary = summary
        self.mode = mode
        self.context = context
    }
}

/// OpenAI Responses API reasoning execution mode.
enum ReasoningMode: String, Codable, CaseIterable {
    case standard
    case pro

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .pro: return "Pro"
        }
    }
}

/// OpenAI Responses API reasoning context reuse across turns.
enum ReasoningContextMode: String, Codable, CaseIterable {
    case auto
    case allTurns = "all_turns"
    case currentTurn = "current_turn"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .allTurns: return "All turns"
        case .currentTurn: return "Current turn"
        }
    }
}

/// OpenAI Responses API `text.verbosity`.
enum TextVerbosity: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        rawValue.capitalized
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

    /// Labels for xAI multi-agent models where effort controls agent count
    /// (low/medium → 4 agents, high/xhigh → 16 agents).
    var xAIMultiAgentDisplayName: String {
        switch self {
        case .none, .minimal, .low:
            return "4 agents (low)"
        case .medium:
            return "4 agents (medium)"
        case .high:
            return "16 agents (high)"
        case .xhigh, .max:
            return "16 agents (xhigh)"
        }
    }

    /// Short label shown as the composer badge — clear enough without full context.
    var badgeName: String? {
        switch self {
        case .none: return nil
        case .minimal: return "Min"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        case .xhigh: return "Ext"
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
    /// The exact effort band the provider reported for this model at fetch time,
    /// when it publishes one. Providers whose bands are enforced rather than clamped
    /// (Router returns `400 Invalid reasoning effort.`) need this for models that
    /// postdate the bundled catalog: without it the effort menu falls back to the
    /// derived OpenAI ladder and can offer a value the model rejects.
    ///
    /// `nil` means "no live band, use `ModelCapabilityRegistry`" — the normal case.
    /// Optional so previously persisted `ModelOverrides` still decode.
    let supportedEfforts: [ReasoningEffort]?

    init(
        type: ReasoningConfigType,
        defaultEffort: ReasoningEffort? = nil,
        defaultBudget: Int? = nil,
        supportedEfforts: [ReasoningEffort]? = nil
    ) {
        self.type = type
        self.defaultEffort = defaultEffort
        self.defaultBudget = defaultBudget
        self.supportedEfforts = supportedEfforts
    }
}

/// Reasoning configuration type.
enum ReasoningConfigType: String, Codable {
    case effort
    case budget
    case toggle
    case none
}
