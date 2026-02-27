import Foundation

/// Accumulates streaming response parts (text, images, videos, thinking, tool calls, search activities)
/// during a streaming response session.
///
/// Extracted from ChatView.startStreamingResponse to reduce that function's complexity.
struct StreamingResponseAccumulator {
    var assistantPartRefs: [StreamedAssistantPartRef] = []
    var assistantTextSegments: [String] = []
    var assistantImageSegments: [ImageContent] = []
    var assistantVideoSegments: [VideoContent] = []
    var assistantThinkingSegments: [ThinkingBlockAccumulator] = []
    var toolCallsByID: [String: ToolCall] = [:]
    var toolCallOrder: [String] = []
    var searchActivitiesByID: [String: SearchActivity] = [:]
    var searchActivityOrder: [String] = []

    mutating func appendTextDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        if let last = assistantPartRefs.last, case .text(let idx) = last {
            assistantTextSegments[idx].append(delta)
        } else {
            let idx = assistantTextSegments.count
            assistantTextSegments.append(delta)
            assistantPartRefs.append(.text(idx))
        }
    }

    mutating func appendImage(_ image: ImageContent) {
        let idx = assistantImageSegments.count
        assistantImageSegments.append(image)
        assistantPartRefs.append(.image(idx))
    }

    mutating func appendVideo(_ video: VideoContent) {
        let idx = assistantVideoSegments.count
        assistantVideoSegments.append(video)
        assistantPartRefs.append(.video(idx))
    }

    mutating func appendThinkingDelta(_ delta: ThinkingDelta) {
        switch delta {
        case .thinking(let textDelta, let signature):
            if textDelta.isEmpty,
               let signature,
               let last = assistantPartRefs.last,
               case .thinking(let idx) = last {
                if assistantThinkingSegments[idx].signature != signature {
                    assistantThinkingSegments[idx].signature = signature
                }
                return
            }

            if let last = assistantPartRefs.last,
               case .thinking(let idx) = last,
               assistantThinkingSegments[idx].signature == signature {
                if !textDelta.isEmpty {
                    assistantThinkingSegments[idx].text.append(textDelta)
                }
                return
            }

            let idx = assistantThinkingSegments.count
            assistantThinkingSegments.append(
                ThinkingBlockAccumulator(text: textDelta, signature: signature)
            )
            assistantPartRefs.append(.thinking(idx))

        case .redacted(let data):
            assistantPartRefs.append(.redacted(RedactedThinkingBlock(data: data)))
        }
    }

    mutating func upsertSearchActivity(_ activity: SearchActivity) {
        if let existing = searchActivitiesByID[activity.id] {
            searchActivitiesByID[activity.id] = existing.merged(with: activity)
        } else {
            searchActivityOrder.append(activity.id)
            searchActivitiesByID[activity.id] = activity
        }
    }

    mutating func upsertToolCall(_ call: ToolCall) {
        if toolCallsByID[call.id] == nil {
            toolCallOrder.append(call.id)
            toolCallsByID[call.id] = call
            return
        }

        let existing = toolCallsByID[call.id]
        let mergedArguments = (existing?.arguments ?? [:]).merging(call.arguments) { _, newValue in newValue }
        let mergedSignature = call.signature ?? existing?.signature
        let mergedName = call.name.isEmpty ? (existing?.name ?? call.name) : call.name
        toolCallsByID[call.id] = ToolCall(
            id: call.id,
            name: mergedName,
            arguments: mergedArguments,
            signature: mergedSignature
        )
    }

    func buildAssistantParts() -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(assistantPartRefs.count)

        for ref in assistantPartRefs {
            switch ref {
            case .text(let idx):
                parts.append(.text(assistantTextSegments[idx]))
            case .image(let idx):
                parts.append(.image(assistantImageSegments[idx]))
            case .video(let idx):
                parts.append(.video(assistantVideoSegments[idx]))
            case .thinking(let idx):
                let thinking = assistantThinkingSegments[idx]
                parts.append(.thinking(ThinkingBlock(text: thinking.text, signature: thinking.signature)))
            case .redacted(let redacted):
                parts.append(.redactedThinking(redacted))
            }
        }

        return parts
    }

    func buildSearchActivities() -> [SearchActivity] {
        searchActivityOrder.compactMap { searchActivitiesByID[$0] }
    }

    func buildToolCalls() -> [ToolCall] {
        toolCallOrder.compactMap { toolCallsByID[$0] }
    }
}
