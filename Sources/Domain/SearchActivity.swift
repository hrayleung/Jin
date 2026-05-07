import Foundation

/// Normalized provider-native web-search activity.
struct SearchActivity: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let status: SearchActivityStatus
    let arguments: [String: AnyCodable]
    let outputIndex: Int?
    let sequenceNumber: Int?

    init(
        id: String,
        type: String,
        status: SearchActivityStatus,
        arguments: [String: AnyCodable] = [:],
        outputIndex: Int? = nil,
        sequenceNumber: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.arguments = arguments
        self.outputIndex = outputIndex
        self.sequenceNumber = sequenceNumber
    }

    func merged(with newer: SearchActivity) -> SearchActivity {
        SearchActivity(
            id: id,
            type: newer.type.isEmpty ? type : newer.type,
            status: newer.status,
            arguments: arguments.merging(newer.arguments) { _, new in new },
            outputIndex: newer.outputIndex ?? outputIndex,
            sequenceNumber: newer.sequenceNumber ?? sequenceNumber
        )
    }
}

/// Status for provider-native web-search activity.
enum SearchActivityStatus: Codable, Sendable, Equatable {
    case inProgress
    case searching
    case completed
    case failed
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "in_progress":
            self = .inProgress
        case "searching":
            self = .searching
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
        case .inProgress:
            return "in_progress"
        case .searching:
            return "searching"
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
        self = SearchActivityStatus(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
