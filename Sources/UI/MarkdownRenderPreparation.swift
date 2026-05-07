import Foundation
import os

enum MarkdownRenderPreparation {
    private struct PreparationCacheEntry {
        var input: String
        var isStreaming: Bool
        var result: PreparedMarkdownResult
    }

    /// Single-slot memo. Hits when the coordinator polls `prepareForRender`
    /// with the same input twice in a row (font/preference re-renders, or a
    /// non-text `renderTick` bump). Streaming flushes never hit because the
    /// text grows each flush; the lock cost on a miss is a single
    /// uncontended unfair-lock acquire (~50ns).
    private static let cache = OSAllocatedUnfairLock<PreparationCacheEntry?>(
        initialState: nil
    )

    static func prepareForRender(_ markdown: String, isStreaming: Bool) -> PreparedMarkdownResult {
        if let cached = cache.withLock({ entry -> PreparedMarkdownResult? in
            guard let entry, entry.isStreaming == isStreaming, entry.input == markdown else {
                return nil
            }
            return entry.result
        }) {
            return cached
        }

        let result = computePrepareForRender(markdown, isStreaming: isStreaming)
        cache.withLock { entry in
            entry = PreparationCacheEntry(
                input: markdown,
                isStreaming: isStreaming,
                result: result
            )
        }
        return result
    }

    private static func computePrepareForRender(_ markdown: String, isStreaming: Bool) -> PreparedMarkdownResult {
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
            repairLine(line)
        }

        return isStreaming ? repairedLines : normalizeBlockSpacing(in: repairedLines)
    }
}
