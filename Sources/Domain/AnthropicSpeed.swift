import Foundation

/// Anthropic Messages API `speed` request values.
///
/// Currently only `fast` is exposed (beta: research preview), enabled on
/// Claude Opus 4.6 and 4.7. Standard speed is represented by `nil` so the
/// field is omitted from the request body.
///
/// Docs: https://platform.claude.com/docs/en/build-with-claude/fast-mode
enum AnthropicSpeed: String, Codable, CaseIterable {
    case fast

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        }
    }

    var badgeText: String {
        switch self {
        case .fast: return "\u{21AF}" // ↯ matches Claude Code's fast-mode glyph
        }
    }
}
