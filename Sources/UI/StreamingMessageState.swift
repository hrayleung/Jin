import Collections
import Combine
import Foundation

@MainActor
final class StreamingMessageState: ObservableObject {
    private static let maxChunkSize = 2048

    var debugContext: StreamingDebugContext?
    private(set) var thinkingChunks: [String] = []
    private(set) var searchActivities: [SearchActivity] = []
    private(set) var codeExecutionActivities: [CodeExecutionActivity] = []
    private(set) var streamingToolCalls: [ToolCall] = []
    private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    private(set) var renderTick: Int = 0
    private(set) var visibleText: String = ""
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
            let parseResult = ArtifactMarkupParser.parse(
                nextTextStorage,
                hidesTrailingIncompleteArtifact: true,
                state: &artifactScanState
            )
            nextVisibleText = parseResult.visibleText
            nextArtifacts = parseResult.artifacts
            nextHasVisibleText = nextVisibleText.trimmedNonEmpty != nil
            parseDurationMs = Int((ProcessInfo.processInfo.systemUptime - parseStartedAt) * 1000)
        }

        guard didMutate else { return }

        objectWillChange.send()
        textStorage = nextTextStorage
        thinkingStorage = nextThinkingStorage
        thinkingChunks = nextThinkingChunks
        visibleText = nextVisibleText
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
                    "threadID": debugContext?.threadID.uuidString ?? "",
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
}

struct StreamingDebugContext {
    let conversationID: UUID
    let threadID: UUID
    let diagnosticRunID: String
}
