import Foundation

final class CodexStreamState: @unchecked Sendable {
    var didEmitMessageStart = false
    var didEmitAssistantText = false
    var assistantTextBuffer = ""
    var didEmitMessageEnd = false
    var didCompleteTurn = false
    var activeTurnID: String?
    var latestUsage: Usage?
}
