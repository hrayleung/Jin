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
    /// Once true, every text flush runs `ArtifactMarkupParser` (angle brackets or
    /// committed artifacts). Until then we skip parse and treat text as passthrough —
    /// the common case for pure markdown streams.
    private var requiresArtifactParse = false
    private var searchActivitiesByID: OrderedDictionary<String, SearchActivity> = [:]
    private var codeExecutionActivitiesByID: OrderedDictionary<String, CodeExecutionActivity> = [:]
    private var hasLoggedFirstDeltaApply = false

    var textContent: String { textStorage }
    var thinkingContent: String { thinkingStorage }

    func reset() {
        objectWillChange.send()
        textStorage = ""
        thinkingStorage = ""
        artifactScanState = .initial
        requiresArtifactParse = false
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
        var didMutate = false
        var didChangeText = false
        var parseDurationMs = 0
        var nextTextStorage = textStorage
        var nextThinkingStorage = thinkingStorage
        var nextThinkingChunks = thinkingChunks
        var nextVisibleText = visibleText
        var nextVisibleTextChunks = visibleTextChunks
        var nextVisibleTextCharacterCount = visibleTextCharacterCount
        var nextArtifacts = artifacts
        var nextHasVisibleText = hasVisibleText
        var nextIsThinkingComplete = isThinkingComplete

        if !textDelta.isEmpty {
            nextTextStorage.append(textDelta)
            if !nextIsThinkingComplete, !nextThinkingChunks.isEmpty {
                nextIsThinkingComplete = true
            }
            didChangeText = true
            didMutate = true
        }

        if !thinkingDelta.isEmpty {
            nextThinkingStorage.append(thinkingDelta)
            appendDelta(thinkingDelta, to: &nextThinkingChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
        }

        if didChangeText {
            let parseStartedAt = ProcessInfo.processInfo.systemUptime

            if !requiresArtifactParse, textDelta.unicodeScalars.contains(where: { $0 == "<" }) {
                requiresArtifactParse = true
            }

            if !requiresArtifactParse {
                // Fast path: no angle brackets yet → no jinArtifact possible.
                nextVisibleText = nextTextStorage
                appendDelta(textDelta, to: &nextVisibleTextChunks, maxChunkSize: Self.maxChunkSize)
                nextVisibleTextCharacterCount += textDelta.count
                nextHasVisibleText = nextHasVisibleText || textDelta.containsNonWhitespace
            } else {
                let parseResult = ArtifactMarkupParser.parse(
                    nextTextStorage,
                    hidesTrailingIncompleteArtifact: true,
                    state: &artifactScanState
                )

                if parseResult.isPassthroughFullText {
                    nextVisibleText = nextTextStorage
                    appendDelta(textDelta, to: &nextVisibleTextChunks, maxChunkSize: Self.maxChunkSize)
                    nextVisibleTextCharacterCount += textDelta.count
                    nextHasVisibleText = nextHasVisibleText || textDelta.containsNonWhitespace
                } else {
                    let chunkUpdate = visibleTextChunkUpdate(
                        previous: visibleText,
                        next: parseResult.visibleText,
                        chunks: visibleTextChunks,
                        prefersIncrementalAppend: !parseResult.hasIncompleteTrailingArtifact
                            && parseResult.artifacts.count == artifacts.count
                    )
                    nextVisibleText = chunkUpdate.visibleText
                    nextVisibleTextChunks = chunkUpdate.chunks
                    nextVisibleTextCharacterCount = chunkUpdate.characterCount
                    nextHasVisibleText = nextVisibleText.containsNonWhitespace
                }

                nextArtifacts = parseResult.artifacts
            }

            parseDurationMs = Int((ProcessInfo.processInfo.systemUptime - parseStartedAt) * 1000)
        }

        guard didMutate else { return }

        objectWillChange.send()
        textStorage = nextTextStorage
        thinkingStorage = nextThinkingStorage
        thinkingChunks = nextThinkingChunks
        visibleText = nextVisibleText
        visibleTextChunks = nextVisibleTextChunks
        visibleTextCharacterCount = nextVisibleTextCharacterCount
        artifacts = nextArtifacts
        hasVisibleText = nextHasVisibleText
        isThinkingComplete = nextIsThinkingComplete
        renderTick &+= 1

        if !hasLoggedFirstDeltaApply, didMutate {
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
