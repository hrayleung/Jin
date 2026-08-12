import Foundation

extension TogetherAdapter {
    func pollVideoUntilDone(
        jobID: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        // Seedance generations commonly take minutes; poll every 10s for ~10 min.
        let pollIntervalNanoseconds: UInt64 = 10_000_000_000
        let maxAttempts = 60
        let pollURL = try validatedURL("\(videoBaseURL)/videos/\(jobID)")

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }

            let request = makeGETRequest(
                url: pollURL,
                apiKey: apiKey,
                includeUserAgent: false
            )

            let (pollData, pollResponse) = try await networkManager.sendRawRequest(request)
            let pollJSON = try decodeVideoJSONObject(pollData)

            if let failure = videoFailureMessage(from: pollJSON) {
                // Only treat as terminal failure when status says so (or non-2xx).
                if case .failed = classifyVideoStatus(json: pollJSON, httpStatus: pollResponse.statusCode) {
                    throw LLMError.providerError(code: "video_generation_failed", message: failure)
                }
            }

            switch classifyVideoStatus(json: pollJSON, httpStatus: pollResponse.statusCode) {
            case .pending:
                continue
            case .completed:
                let (localURL, mimeType) = try await downloadCompletedVideo(responseJSON: pollJSON)
                continuation.yield(.contentDelta(.video(VideoContent(mimeType: mimeType, data: nil, url: localURL))))
                continuation.yield(.messageEnd(usage: nil))
                continuation.finish()
                return
            case .failed(let message):
                throw LLMError.providerError(
                    code: "video_generation_failed",
                    message: message ?? "Video generation failed on the server."
                )
            }
        }

        throw LLMError.providerError(
            code: "video_generation_timeout",
            message: "Together video generation timed out after polling for ~10 minutes."
        )
    }

    func downloadCompletedVideo(
        responseJSON: [String: Any]
    ) async throws -> (localURL: URL, mimeType: String) {
        guard let videoURLString = extractVideoURL(from: responseJSON),
              let videoURL = URL(string: videoURLString),
              let scheme = videoURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMError.decodingError(
                message: "Together video job completed without a downloadable video_url."
            )
        }

        // Together hosts completed clips on signed CDN URLs; no auth header needed.
        return try await VideoAttachmentUtility.downloadToLocal(
            from: videoURL,
            networkManager: networkManager,
            authHeader: nil
        )
    }

    func extractVideoURL(from json: [String: Any]) -> String? {
        if let outputs = json["outputs"] as? [String: Any],
           let url = stringValue(outputs["video_url"]) ?? stringValue(outputs["url"]) {
            return url
        }
        if let outputsArray = json["outputs"] as? [[String: Any]],
           let first = outputsArray.first,
           let url = stringValue(first["video_url"]) ?? stringValue(first["url"]) {
            return url
        }
        if let outputsStrings = json["outputs"] as? [String],
           let first = outputsStrings.first {
            return stringValue(first)
        }
        if let output = json["output"] as? [String: Any],
           let url = stringValue(output["video_url"]) ?? stringValue(output["url"]) {
            return url
        }
        if let outputArray = json["output"] as? [[String: Any]],
           let first = outputArray.first,
           let url = stringValue(first["video_url"]) ?? stringValue(first["url"]) {
            return url
        }
        if let outputStrings = json["output"] as? [String],
           let first = outputStrings.first {
            return stringValue(first)
        }
        return stringValue(json["video_url"])
            ?? stringValue(json["url"])
    }

    func extractVideoJobID(from json: [String: Any]) -> String? {
        if let id = stringValue(json["id"]) ?? stringValue(json["video_id"]) ?? stringValue(json["job_id"]) ?? stringValue(json["request_id"]) {
            return id
        }
        if let data = json["data"] as? [String: Any] {
            return stringValue(data["id"]) ?? stringValue(data["job_id"]) ?? stringValue(data["video_id"])
        }
        return nil
    }

    func classifyVideoStatus(json: [String: Any], httpStatus: Int) -> TogetherVideoPollStatus {
        // Official statuses: in_progress | completed | failed
        // (docs.together.ai/reference/get-videos-id)
        let status = stringValue(json["status"])?.lowercased()

        switch status {
        case "pending", "queued", "processing", "in_progress", "running":
            return .pending
        case "completed", "complete", "done", "success":
            return .completed
        case "failed", "error", "cancelled", "canceled", "expired":
            return .failed(videoFailureMessage(from: json))
        default:
            break
        }

        if extractVideoURL(from: json) != nil {
            return .completed
        }

        if httpStatus >= 400 {
            return .failed(videoFailureMessage(from: json) ?? "HTTP \(httpStatus)")
        }

        return .pending
    }

    func videoFailureMessage(from json: [String: Any]) -> String? {
        if let direct = stringValue(json["message"]) {
            return direct
        }
        if let error = stringValue(json["error"]) {
            return error
        }
        if let errorObject = json["error"] as? [String: Any] {
            return stringValue(errorObject["message"])
                ?? stringValue(errorObject["detail"])
                ?? stringValue(errorObject["reason"])
        }
        if let detail = stringValue(json["detail"]) {
            return detail
        }
        if let failureReason = stringValue(json["failure_reason"]) {
            return failureReason
        }
        if let errorMessage = stringValue(json["error_message"]) {
            return errorMessage
        }
        if let data = json["data"] as? [String: Any] {
            return videoFailureMessage(from: data)
        }
        return nil
    }

    func decodeVideoJSONObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError(message: "Together video generation returned non-JSON response.")
        }
        return json
    }

    func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmedNonEmpty
    }
}

enum TogetherVideoPollStatus {
    case pending
    case completed
    case failed(String?)
}
