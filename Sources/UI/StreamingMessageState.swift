import Collections
import Combine
import Foundation

@MainActor
final class StreamingMessageState: ObservableObject {
    private static let maxChunkSize = 2048

    var debugContext: StreamingDebugContext?
    private(set) var thinkingChunks: [String] = []
    private(set) var visibleTextChunks: [String] = []
    private(set) var searchActivities: [SearchActivity] = []
    private(set) var codeExecutionActivities: [CodeExecutionActivity] = []
    private(set) var streamingToolCalls: [ToolCall] = []
    private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    private(set) var renderTick: Int = 0
    private(set) var visibleText: String = ""
    private(set) var visibleTextCharacterCount: Int = 0
    private(set) var artifacts: [ParsedArtifact] = []
    private(set) var hasVisibleText: Bool = false
    private(set) var isThinkingComplete: Bool = false

    private var textStorage = ""
    private var thinkingStorage = ""
    private var artifactScanState = ArtifactMarkupParser.ScanState.initial
    private var searchActivitiesByID: OrderedDictionary<String, SearchActivity> = [:]
    private var codeExecutionActivitiesByID: OrderedDictionary<String, CodeExecutionActivity> = [:]
    private var hasLoggedFirstDeltaApply = false

    var textContent: String { textStorage }
    var thinkingContent: String { thinkingStorage }

    /// Anything the live bubble would actually paint. Empty after a tool-turn
    /// persist/reset — the timeline then collapses this row instead of
    /// showing a second Generating / Running card.
    var hasVisiblePresentation: Bool {
        hasVisibleText
            || !thinkingChunks.isEmpty
            || !searchActivities.isEmpty
            || !codeExecutionActivities.isEmpty
            || !streamingToolCalls.isEmpty
            || !artifacts.isEmpty
    }

    func reset() {
        objectWillChange.send()
        textStorage = ""
        thinkingStorage = ""
        artifactScanState = .initial
        thinkingChunks = []
        searchActivities = []
        codeExecutionActivities = []
        streamingToolCalls = []
        toolResultsByCallID = [:]
        searchActivitiesByID = [:]
        codeExecutionActivitiesByID = [:]
        hasLoggedFirstDeltaApply = false
        visibleText = ""
        visibleTextChunks = []
        visibleTextCharacterCount = 0
        artifacts = []
        hasVisibleText = false
        isThinkingComplete = false
        renderTick = 0
    }

    func appendDeltas(textDelta: String, thinkingDelta: String) {
        let appendStartedAt = ProcessInfo.processInfo.systemUptime
        let didChangeText = !textDelta.isEmpty
        guard didChangeText || !thinkingDelta.isEmpty else { return }

        var parseDurationMs = 0

        // Mutate the stored properties in place. The previous implementation
        // staged every field into `next*` shadow copies and committed at the
        // end; for the two monotonic string buffers that second reference
        // defeated copy-on-write, so every flush recopied the entire
        // accumulated response (O(n) per flush, O(n²) over a long reply).
        // In-place appends on uniquely-referenced strings are amortized
        // O(delta). `objectWillChange` still precedes the first mutation.
        objectWillChange.send()

        if didChangeText {
            textStorage.append(textDelta)
            if !isThinkingComplete, !thinkingChunks.isEmpty {
                isThinkingComplete = true
            }
        }

        if !thinkingDelta.isEmpty {
            thinkingStorage.append(thinkingDelta)
            appendDelta(thinkingDelta, to: &thinkingChunks, maxChunkSize: Self.maxChunkSize)
        }

        if didChangeText {
            let parseStartedAt = ProcessInfo.processInfo.systemUptime
            let parseResult = ArtifactMarkupParser.parse(
                textStorage,
                hidesTrailingIncompleteArtifact: true,
                state: &artifactScanState
            )

            if parseResult.isPassthroughFullText {
                // Passthrough guarantees visibleText mirrors textStorage (the
                // chunk bookkeeping below has always relied on that), so
                // append the delta to visibleText's own buffer rather than
                // aliasing textStorage — aliasing would force the next
                // in-place append to copy the whole string again.
                visibleText.append(textDelta)
                appendDelta(textDelta, to: &visibleTextChunks, maxChunkSize: Self.maxChunkSize)
                visibleTextCharacterCount += textDelta.count
                hasVisibleText = hasVisibleText || textDelta.containsNonWhitespace
            } else {
                let chunkUpdate = visibleTextChunkUpdate(
                    previous: visibleText,
                    next: parseResult.visibleText,
                    chunks: visibleTextChunks,
                    prefersIncrementalAppend: !parseResult.hasIncompleteTrailingArtifact
                        && parseResult.artifacts.count == artifacts.count
                )
                visibleText = chunkUpdate.visibleText
                visibleTextChunks = chunkUpdate.chunks
                visibleTextCharacterCount = chunkUpdate.characterCount
                hasVisibleText = visibleText.containsNonWhitespace
            }

            artifacts = parseResult.artifacts
            parseDurationMs = Int((ProcessInfo.processInfo.systemUptime - parseStartedAt) * 1000)
        }

        renderTick &+= 1

        if !hasLoggedFirstDeltaApply {
            hasLoggedFirstDeltaApply = true
            let totalDurationMs = Int((ProcessInfo.processInfo.systemUptime - appendStartedAt) * 1000)
            // #region agent log
            ChatDiagnosticLogger.log(
                runId: debugContext?.diagnosticRunID ?? "unknown",
                hypothesisId: "H7",
                message: "chat_first_delta_apply_complete",
                data: [
                    "conversationID": debugContext?.conversationID.uuidString ?? "",
                    "textDeltaCount": String(textDelta.count),
                    "thinkingDeltaCount": String(thinkingDelta.count),
                    "parseDurationMs": String(parseDurationMs),
                    "totalDurationMs": String(totalDurationMs),
                    "visibleTextCount": String(visibleText.count)
                ]
            )
            // #endregion
        }
    }

    func appendTextDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        appendDeltas(textDelta: delta, thinkingDelta: "")
    }

    func appendThinkingDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        appendDeltas(textDelta: "", thinkingDelta: delta)
    }

    func markThinkingComplete() {
        guard !isThinkingComplete, !thinkingChunks.isEmpty else { return }
        objectWillChange.send()
        isThinkingComplete = true
        renderTick &+= 1
    }

    func upsertSearchActivity(_ activity: SearchActivity) {
        objectWillChange.send()
        if let existing = searchActivitiesByID[activity.id] {
            searchActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            searchActivitiesByID[activity.id] = activity
        }
        searchActivities = Array(searchActivitiesByID.values)
        renderTick &+= 1
    }

    func upsertCodeExecutionActivity(_ activity: CodeExecutionActivity) {
        objectWillChange.send()
        if let existing = codeExecutionActivitiesByID[activity.id] {
            codeExecutionActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            codeExecutionActivitiesByID[activity.id] = activity
        }
        codeExecutionActivities = Array(codeExecutionActivitiesByID.values)
        renderTick &+= 1
    }

    func setToolCalls(_ toolCalls: [ToolCall]) {
        objectWillChange.send()
        streamingToolCalls = toolCalls
        toolResultsByCallID = [:]
        renderTick &+= 1
    }

    func upsertToolResult(_ result: ToolResult) {
        guard streamingToolCalls.contains(where: { $0.id == result.toolCallID }) else { return }
        objectWillChange.send()
        toolResultsByCallID[result.toolCallID] = result
        renderTick &+= 1
    }

    private func appendDelta(_ delta: String, to chunks: inout [String], maxChunkSize: Int) {
        if chunks.isEmpty {
            chunks.append(delta)
        } else {
            chunks[chunks.count - 1].append(delta)
        }

        while let lastChunk = chunks.last, lastChunk.count > maxChunkSize {
            let maxIndex = lastChunk.index(lastChunk.startIndex, offsetBy: maxChunkSize)
            let candidate = lastChunk[..<maxIndex]

            let splitIndex = candidate.lastIndex(of: "\n").map { lastChunk.index(after: $0) } ?? maxIndex
            let prefix = String(lastChunk[..<splitIndex])
            let suffix = String(lastChunk[splitIndex...])

            chunks[chunks.count - 1] = prefix
            if !suffix.isEmpty {
                chunks.append(suffix)
            }
        }
    }

    private func visibleTextChunkUpdate(
        previous: String,
        next: String,
        chunks: [String],
        prefersIncrementalAppend: Bool
    ) -> (visibleText: String, chunks: [String], characterCount: Int) {
        if prefersIncrementalAppend, next.count >= visibleTextCharacterCount {
            let suffixStart = next.index(next.startIndex, offsetBy: visibleTextCharacterCount)
            let suffix = String(next[suffixStart...])
            guard !suffix.isEmpty else {
                return (next, chunks, visibleTextCharacterCount)
            }

            var updatedChunks = chunks
            appendDelta(suffix, to: &updatedChunks, maxChunkSize: Self.maxChunkSize)
            return (next, updatedChunks, visibleTextCharacterCount + suffix.count)
        }

        guard next.hasPrefix(previous) else {
            return (next, chunksRebuilt(from: next), next.count)
        }

        let suffixStart = next.index(next.startIndex, offsetBy: previous.count)
        let suffix = String(next[suffixStart...])
        guard !suffix.isEmpty else {
            return (next, chunks, visibleTextCharacterCount)
        }

        var updatedChunks = chunks
        appendDelta(suffix, to: &updatedChunks, maxChunkSize: Self.maxChunkSize)
        return (next, updatedChunks, visibleTextCharacterCount + suffix.count)
    }

    private func chunksRebuilt(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        appendDelta(text, to: &chunks, maxChunkSize: Self.maxChunkSize)
        return chunks
    }
}

struct StreamingDebugContext {
    let conversationID: UUID
    let diagnosticRunID: String
}
