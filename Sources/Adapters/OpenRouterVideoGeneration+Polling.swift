import Foundation

extension OpenRouterAdapter {
    func pollVideoUntilDone(
        jobID: String,
        initialPollURLString: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let pollIntervalNanoseconds: UInt64 = 10_000_000_000
        let maxAttempts = 60
        let pollURL = try resolvedPollingURL(jobID: jobID, pollURLString: initialPollURLString)

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }

            let request = makeGETRequest(
                url: pollURL,
                apiKey: apiKey,
                additionalHeaders: openRouterHeaders,
                includeUserAgent: false
            )

            let (pollData, pollResponse) = try await networkManager.sendRawRequest(request)
            let pollJSON = try decodeJSONObject(pollData)

            if let failure = failureMessage(from: pollJSON) {
                throw LLMError.providerError(code: "video_generation_failed", message: failure)
            }

            switch classifyVideoStatus(json: pollJSON, httpStatus: pollResponse.statusCode) {
            case .pending:
                continue
            case .completed:
                let (localURL, mimeType) = try await downloadCompletedVideo(
                    jobID: jobID,
                    responseJSON: pollJSON
                )
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
            message: "OpenRouter video generation timed out after polling for ~10 minutes."
        )
    }

    func resolvedPollingURL(jobID: String, pollURLString: String?) throws -> URL {
        if let pollURLString,
           let pollURL = URL(string: pollURLString),
           isTrustedOpenRouterURL(pollURL) {
            return pollURL
        }

        return try validatedURL("\(baseURL)/videos/\(jobID)")
    }

    func downloadCompletedVideo(
        jobID: String,
        responseJSON: [String: Any]
    ) async throws -> (localURL: URL, mimeType: String) {
        let contentEndpoint = OpenRouterVideoDownloadTarget(
            url: try validatedURL("\(baseURL)/videos/\(jobID)/content?index=0"),
            requiresAuthorization: true
        )

        do {
            return try await downloadVideo(from: contentEndpoint)
        } catch {
            let unsignedTarget = resolvedUnsignedDownloadTarget(responseJSON: responseJSON)
            if let unsignedTarget {
                return try await downloadVideo(from: unsignedTarget)
            }
            throw error
        }
    }

    func downloadVideo(
        from target: OpenRouterVideoDownloadTarget
    ) async throws -> (localURL: URL, mimeType: String) {
        try await VideoAttachmentUtility.downloadToLocal(
            from: target.url,
            networkManager: networkManager,
            authHeader: target.requiresAuthorization
                ? (key: "Authorization", value: "Bearer \(apiKey)")
                : nil
        )
    }

    func resolvedUnsignedDownloadTarget(responseJSON: [String: Any]) -> OpenRouterVideoDownloadTarget? {
        guard let unsignedURLs = responseJSON["unsigned_urls"] as? [String],
              let first = unsignedURLs.first,
              let url = URL(string: first),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return nil
        }

        return OpenRouterVideoDownloadTarget(
            url: url,
            requiresAuthorization: false
        )
    }

    func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError(message: "OpenRouter video generation returned non-JSON response.")
        }
        return json
    }

    func extractVideoJobID(from json: [String: Any]) -> String? {
        stringValue(json["id"])
            ?? stringValue(json["generation_id"])
            ?? stringValue(json["video_id"])
            ?? stringValue(json["request_id"])
    }

    func classifyVideoStatus(json: [String: Any], httpStatus: Int) -> OpenRouterVideoPollStatus {
        let status = stringValue(json["status"])?.lowercased()

        switch status {
        case "pending", "queued", "processing", "in_progress":
            return .pending
        case "completed", "complete", "done", "success":
            return .completed
        case "failed", "error", "cancelled", "canceled", "expired":
            return .failed(failureMessage(from: json))
        default:
            break
        }

        if responseHasVideoOutput(json) {
            return .completed
        }

        if httpStatus >= 400 {
            return .failed(failureMessage(from: json) ?? "HTTP \(httpStatus)")
        }

        return .pending
    }

    func responseHasVideoOutput(_ json: [String: Any]) -> Bool {
        if let unsignedURLs = json["unsigned_urls"] as? [String], !unsignedURLs.isEmpty {
            return true
        }
        if let output = json["output"] as? [[String: Any]], !output.isEmpty {
            return true
        }
        return false
    }

    func failureMessage(from json: [String: Any]) -> String? {
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
        if let data = json["data"] as? [String: Any] {
            return failureMessage(from: data)
        }
        return nil
    }

    func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmedNonEmpty
    }

    func isTrustedOpenRouterURL(_ url: URL) -> Bool {
        OpenRouterProviderSupport.isTrustedURL(url, forBaseURL: baseURL)
    }

    func normalizedPort(for url: URL) -> Int? {
        OpenRouterProviderSupport.normalizedHTTPPort(for: url)
    }
}

enum OpenRouterVideoPollStatus {
    case pending
    case completed
    case failed(String?)
}

struct OpenRouterVideoDownloadTarget {
    let url: URL
    let requiresAuthorization: Bool
}
