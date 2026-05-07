import Foundation

enum MarkdownRepairMode: String, Equatable, Sendable {
    case none
    case repaired
}

struct MarkdownPreparationDiagnostics: Equatable, Sendable {
    let repairMode: MarkdownRepairMode
    let anomalyScoreBefore: Int
    let anomalyScoreAfter: Int
}

struct PreparedMarkdownResult: Equatable, Sendable {
    let text: String
    let didChange: Bool
    let diagnostics: MarkdownPreparationDiagnostics
}

extension PreparedMarkdownResult {
    static func passthrough(_ text: String) -> Self {
        Self(
            text: text,
            didChange: false,
            diagnostics: MarkdownPreparationDiagnostics(
                repairMode: .none,
                anomalyScoreBefore: 0,
                anomalyScoreAfter: 0
            )
        )
    }
}
