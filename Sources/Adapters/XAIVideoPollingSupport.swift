import Foundation

enum XAIVideoPollingSupport {
    enum PollStatus: Equatable {
        case pending
        case done
        case expired
        case failed(String?)
    }

    static func trackDecodeFailures(
        statusResponse: XAIVideoStatusResponse?,
        rawJSON: [String: Any]?,
        httpStatus: Int,
        rawBody: String,
        consecutiveFailures: Int,
        maxFailures: Int
    ) throws -> Int {
        guard statusResponse == nil,
              httpStatus >= 200,
              httpStatus < 300 else {
            return 0
        }

        let rawHasStatusSignal: Bool = {
            guard let json = rawJSON else { return false }
            for key in ["status", "state"] {
                if json[key] is String { return true }
            }
            return false
        }()

        guard !rawHasStatusSignal else { return 0 }

        let updated = consecutiveFailures + 1
        if updated >= maxFailures {
            throw LLMError.decodingError(
                message: "xAI video poll response could not be decoded after \(maxFailures) consecutive attempts. Last response: \(String(rawBody.prefix(500)))"
            )
        }
        return updated
    }

    static func resolveStatus(
        codable: XAIVideoStatusResponse?,
        rawJSON: [String: Any]?,
        httpStatus: Int
    ) -> PollStatus {
        if let status = codable?.status?.lowercased(),
           let resolved = classifyStatusString(status) {
            return resolved
        }

        if let json = rawJSON {
            for key in ["status", "state"] {
                if let val = json[key] as? String,
                   let resolved = classifyStatusString(val.lowercased(), failureMessage: extractFailureMessage(from: json)) {
                    return resolved
                }
            }

            if extractVideoURL(codable: codable, rawJSON: rawJSON) != nil {
                return .done
            }
        }

        if httpStatus == 404 || httpStatus == 410 {
            return .expired
        }
        if httpStatus >= 500 {
            let message = extractFailureMessage(from: rawJSON)
            return .failed(message ?? "Server error (HTTP \(httpStatus))")
        }
        if httpStatus >= 400 {
            let message = extractFailureMessage(from: rawJSON)
            return .failed(message ?? "HTTP \(httpStatus)")
        }

        return .pending
    }

    static func classifyStatusString(_ status: String, failureMessage: String? = nil) -> PollStatus? {
        switch status {
        case "done", "complete", "completed", "success":
            return .done
        case "expired":
            return .expired
        case "failed", "error":
            return .failed(failureMessage)
        case "pending", "in_progress", "processing", "queued":
            return .pending
        default:
            return nil
        }
    }

    static func extractFailureMessage(from json: [String: Any]?) -> String? {
        guard let json else { return nil }

        if let message = nonEmptyMessage(json["message"]) {
            return message
        }
        if let errorText = nonEmptyMessage(json["error"]) {
            return errorText
        }

        if let errorObject = json["error"] as? [String: Any] {
            if let message = nonEmptyMessage(errorObject["message"]) {
                return message
            }
            if let detail = nonEmptyMessage(errorObject["detail"]) {
                return detail
            }
            if let reason = nonEmptyMessage(errorObject["reason"]) {
                return reason
            }
        }

        if let errors = json["errors"] as? [[String: Any]] {
            for item in errors {
                if let nested = extractFailureMessage(from: item) {
                    return nested
                }
            }
        }

        for nestedKey in ["response", "data", "result"] {
            if let nested = extractFailureMessage(from: json[nestedKey] as? [String: Any]) {
                return nested
            }
        }

        return nil
    }

    static func nonEmptyMessage(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        return text.trimmedNonEmpty
    }

    static func extractVideoURL(codable: XAIVideoStatusResponse?, rawJSON: [String: Any]?) -> URL? {
        if let urlString = codable?.resolvedVideo?.url, let url = URL(string: urlString) {
            return url
        }

        guard let json = rawJSON else { return nil }

        if let video = json["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let response = json["response"] as? [String: Any],
           let video = response["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let result = json["result"] as? [String: Any] {
            if let video = result["video"] as? [String: Any],
               let urlString = video["url"] as? String,
               let url = URL(string: urlString) {
                return url
            }
            if let urlString = result["url"] as? String, let url = URL(string: urlString) {
                return url
            }
        }

        if let data = json["data"] as? [String: Any],
           let video = data["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let urlString = json["url"] as? String,
           let url = URL(string: urlString),
           urlString.contains("video") || urlString.contains(".mp4") || urlString.contains("vidgen") {
            return url
        }

        return nil
    }
}
