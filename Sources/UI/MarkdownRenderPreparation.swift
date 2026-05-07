import Foundation

enum MarkdownRenderPreparation {
    static func prepareForRender(_ markdown: String, isStreaming: Bool) -> PreparedMarkdownResult {
        guard !markdown.isEmpty else {
            return .passthrough(markdown)
        }

        let scoreBefore = anomalyScore(in: markdown)
        guard scoreBefore > 0 else {
            return PreparedMarkdownResult(
                text: markdown,
                didChange: false,
                diagnostics: MarkdownPreparationDiagnostics(
                    repairMode: .none,
                    anomalyScoreBefore: scoreBefore,
                    anomalyScoreAfter: scoreBefore
                )
            )
        }

        let repaired = repairMarkdown(markdown, isStreaming: isStreaming)
        let scoreAfter = anomalyScore(in: repaired)
        let shouldUseRepair = repaired != markdown && scoreAfter <= scoreBefore
        let output = shouldUseRepair ? repaired : markdown

        return PreparedMarkdownResult(
            text: output,
            didChange: output != markdown,
            diagnostics: MarkdownPreparationDiagnostics(
                repairMode: output == markdown ? .none : .repaired,
                anomalyScoreBefore: scoreBefore,
                anomalyScoreAfter: output == markdown ? scoreBefore : scoreAfter
            )
        )
    }

    static func prepare(_ markdown: String) -> String {
        prepareForRender(markdown, isStreaming: false).text
    }

    static func repairMarkdown(_ markdown: String, isStreaming: Bool) -> String {
        let repairedLines = transformOutsideProtectedBlocks(in: markdown) { line in
            MarkdownStructuralRepair.repairLine(line)
        }
        let completed = MarkdownInlineCompletion.completeUnclosedInlineMarkers(in: repairedLines)
        return isStreaming ? completed : normalizeBlockSpacing(in: completed)
    }
}
