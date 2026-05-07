import Foundation

// MARK: - Code Interpreter Streaming Events

struct ResponsesAPICodeInterpreterStatusEvent: Codable {
    let itemId: String
    let outputIndex: Int?
    let sequenceNumber: Int?
}

struct ResponsesAPICodeInterpreterCodeDeltaEvent: Codable {
    let itemId: String
    let delta: String
    let outputIndex: Int?
    let sequenceNumber: Int?
}

struct ResponsesAPICodeInterpreterCodeDoneEvent: Codable {
    let itemId: String
    let code: String?
    let outputIndex: Int?
    let sequenceNumber: Int?
}

/// Mutable state for tracking OpenAI code interpreter streaming progress.
struct OpenAICodeInterpreterState {
    var currentItemID: String?
    var codeBuffer: String = ""
}
