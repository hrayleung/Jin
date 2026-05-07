import Foundation

// MARK: - Streaming Event Types

struct ResponsesAPICreatedEvent: Codable {
    let response: ResponseInfo

    struct ResponseInfo: Codable {
        let id: String
    }
}

struct ResponsesAPIOutputTextDeltaEvent: Codable {
    let delta: String
}

struct ResponsesAPIReasoningTextDeltaEvent: Codable {
    let delta: String
}

struct ResponsesAPIReasoningSummaryTextDeltaEvent: Codable {
    let delta: String
}

struct ResponsesAPIFunctionCallArgumentsDeltaEvent: Codable {
    let itemId: String
    let delta: String
}

struct ResponsesAPIFunctionCallArgumentsDoneEvent: Codable {
    let itemId: String
    let arguments: String
}

struct ResponsesAPICompletedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let id: String?
        let citations: [String]?
        let output: [ResponsesAPIOutputItem]?
        let usage: ResponsesAPIUsageInfo?

        func toUsage() -> Usage? {
            usage?.toUsage()
        }
    }
}

struct ResponsesAPIIncompleteEvent: Codable {
    let response: Response

    struct Response: Codable {
        let id: String?
        let status: String?
        let incompleteDetails: ResponsesAPIIncompleteDetails?
        let usage: ResponsesAPIUsageInfo?

        func toUsage() -> Usage? {
            usage?.toUsage()
        }

        var incompleteNoticeMarkdown: String? {
            ResponsesAPIIncompleteDetails.noticeMarkdown(
                status: status,
                reason: incompleteDetails?.reason
            )
        }
    }
}

struct ResponsesAPIFailedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let error: ErrorInfo?

        struct ErrorInfo: Codable {
            let code: String?
            let message: String
        }
    }
}

struct ResponsesAPIOutputItemDoneEvent: Codable {
    let outputIndex: Int?
    let sequenceNumber: Int?
    let item: ResponsesAPIOutputItemAddedEvent.Item
}

struct ResponsesAPIWebSearchCallStatusEvent: Codable {
    let outputIndex: Int?
    let itemId: String
    let sequenceNumber: Int?
}
