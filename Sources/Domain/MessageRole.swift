import Foundation

/// Role of a message in the conversation
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}
