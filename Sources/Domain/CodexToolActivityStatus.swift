import Foundation

/// Status of a Codex server-side tool execution.
enum CodexToolActivityStatus: Codable, Sendable, Equatable {
    case running
    case completed
    case failed
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "running":
            self = .running
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .running:
            return "running"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = CodexToolActivityStatus(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
