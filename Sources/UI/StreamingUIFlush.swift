import Foundation

struct StreamingUIFlush {
    let textDelta: String
    let thinkingDelta: String
    let isFirstFlush: Bool
    let force: Bool
    /// Latest full tool-call list when tools changed this window; nil if unchanged.
    let toolCalls: [ToolCall]?
    let searchActivities: [SearchActivity]
    let codeExecutionActivities: [CodeExecutionActivity]
}
