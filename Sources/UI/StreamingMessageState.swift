import Collections
import Combine
import Foundation

@MainActor
final class StreamingMessageState: ObservableObject {
    private static let maxChunkSize = 2048

    var debugContext: StreamingDebugContext?
    @Published private(set) var thinkingChunks: [String] = []
    @Published private(set) var searchActivities: [SearchActivity] = []
    @Published private(set) var codeExecutionActivities: [CodeExecutionActivity] = []
    @Published private(set) var codexToolActivities: [CodexToolActivity] = []
    @Published private(set) var agentToolActivities: [CodexToolActivity] = []
    @Published private(set) var streamingToolCalls: [ToolCall] = []
    @Published private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var visibleText: String = ""
    @Published private(set) var artifacts: [ParsedArtifact] = []
    @Published private(set) var hasVisibleText: Bool = false
    @Published private(set) var isThinkingComplete: Bool = false

    private var textStorage = ""
    private var thinkingStorage = ""
    private var searchActivitiesByID: OrderedDictionary<String, SearchActivity> = [:]
    private var codeExecutionActivitiesByID: OrderedDictionary<String, CodeExecutionActivity> = [:]
    private var codexToolActivitiesByID: OrderedDictionary<String, CodexToolActivity> = [:]
    private var agentToolActivitiesByID: OrderedDictionary<String, CodexToolActivity> = [:]
    private var hasLoggedFirstDeltaApply = false

    var textContent: String { textStorage }
    var thinkingContent: String { thinkingStorage }

    func reset() {
        textStorage = ""
        thinkingStorage = ""
        thinkingChunks = []
        searchActivities = []
        codeExecutionActivities = []
        codexToolActivities = []
        agentToolActivities = []
        streamingToolCalls = []
        toolResultsByCallID = [:]
        searchActivitiesByID = [:]
        codeExecutionActivitiesByID = [:]
        codexToolActivitiesByID = [:]
        agentToolActivitiesByID = [:]
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

        if !textDelta.isEmpty {
            textStorage.append(textDelta)
            if !isThinkingComplete, !thinkingChunks.isEmpty {
                isThinkingComplete = true
            }
            didChangeText = true
            didMutate = true
        }

        if !thinkingDelta.isEmpty {
            thinkingStorage.append(thinkingDelta)
            appendDelta(thinkingDelta, to: &thinkingChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
        }

        if didChangeText {
            let parseStartedAt = ProcessInfo.processInfo.systemUptime
            updateParsedStreamingContent()
            parseDurationMs = Int((ProcessInfo.processInfo.systemUptime - parseStartedAt) * 1000)
        }

        if didMutate {
            renderTick &+= 1
        }

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
        isThinkingComplete = true
        renderTick &+= 1
    }

    func upsertSearchActivity(_ activity: SearchActivity) {
        if let existing = searchActivitiesByID[activity.id] {
            searchActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            searchActivitiesByID[activity.id] = activity
        }
        searchActivities = Array(searchActivitiesByID.values)
        renderTick &+= 1
    }

    func upsertCodeExecutionActivity(_ activity: CodeExecutionActivity) {
        if let existing = codeExecutionActivitiesByID[activity.id] {
            codeExecutionActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            codeExecutionActivitiesByID[activity.id] = activity
        }
        codeExecutionActivities = Array(codeExecutionActivitiesByID.values)
        renderTick &+= 1
    }

    func upsertCodexToolActivity(_ activity: CodexToolActivity) {
        if let existing = codexToolActivitiesByID[activity.id] {
            codexToolActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            codexToolActivitiesByID[activity.id] = activity
        }
        codexToolActivities = Array(codexToolActivitiesByID.values)
        renderTick &+= 1
    }

    func upsertAgentToolActivity(_ activity: CodexToolActivity) {
        if let existing = agentToolActivitiesByID[activity.id] {
            agentToolActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            agentToolActivitiesByID[activity.id] = activity
        }
        agentToolActivities = Array(agentToolActivitiesByID.values)
        renderTick &+= 1
    }

    func setToolCalls(_ toolCalls: [ToolCall]) {
        streamingToolCalls = toolCalls
        toolResultsByCallID = [:]
        renderTick &+= 1
    }

    func upsertToolResult(_ result: ToolResult) {
        guard streamingToolCalls.contains(where: { $0.id == result.toolCallID }) else { return }
        toolResultsByCallID[result.toolCallID] = result
        renderTick &+= 1
    }

    private func updateParsedStreamingContent() {
        let parseResult = ArtifactMarkupParser.parse(textStorage, hidesTrailingIncompleteArtifact: true)
        visibleText = parseResult.visibleText
        artifacts = parseResult.artifacts
        hasVisibleText = !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
