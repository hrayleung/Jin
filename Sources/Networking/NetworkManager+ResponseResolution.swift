import Foundation
import Alamofire

extension NetworkManager {
    enum HTTPErrorDisposition {
        case failOnErrorStatus
        case allowAnyStatus
    }

    struct RequestExecutionFailure: Error {
        let underlyingError: Error
        let response: HTTPURLResponse?
        let responseBody: Data?
    }

    func resolveDataResponse(
        _ dataResponse: DataResponse<Data, AFError>,
        httpErrorDisposition: HTTPErrorDisposition
    ) throws -> (Data, HTTPURLResponse) {
        let data = dataResponse.data ?? Data()

        if let failure = resolvedRequestExecutionFailure(
            from: dataResponse.error,
            response: dataResponse.response,
            responseBody: data
        ) {
            throw failure
        }

        guard let httpResponse = dataResponse.response else {
            throw missingHTTPResponseFailure()
        }

        if httpErrorDisposition == .failOnErrorStatus, httpResponse.statusCode >= 400 {
            throw try httpStatusFailure(response: httpResponse, responseBody: data)
        }

        return (data, httpResponse)
    }

    nonisolated func resolveStreamCompletion(
        completion: DataStreamRequest.Completion,
        response: HTTPURLResponse?,
        responseBody: Data?
    ) -> Result<Void, RequestExecutionFailure> {
        if let failure = resolvedRequestExecutionFailure(
            from: completion.error,
            response: response,
            responseBody: responseBody
        ) {
            return .failure(failure)
        }

        guard let httpResponse = response else {
            return .failure(missingHTTPResponseFailure())
        }

        if httpResponse.statusCode >= 400 {
            do {
                return .failure(
                    try httpStatusFailure(response: httpResponse, responseBody: responseBody)
                )
            } catch {
                return .failure(
                    RequestExecutionFailure(
                        underlyingError: error,
                        response: httpResponse,
                        responseBody: responseBody
                    )
                )
            }
        }

        return .success(())
    }

    nonisolated func missingHTTPResponseFailure() -> RequestExecutionFailure {
        RequestExecutionFailure(
            underlyingError: LLMError.networkError(underlying: URLError(.badServerResponse)),
            response: nil,
            responseBody: nil
        )
    }

    nonisolated func httpStatusFailure(
        response: HTTPURLResponse,
        responseBody: Data?
    ) throws -> RequestExecutionFailure {
        RequestExecutionFailure(
            underlyingError: try parseHTTPError(
                statusCode: response.statusCode,
                data: responseBody ?? Data(),
                headers: response.allHeaderFields
            ),
            response: response,
            responseBody: responseBody
        )
    }

    nonisolated func resolvedRequestExecutionFailure(
        from afError: AFError?,
        response: HTTPURLResponse?,
        responseBody: Data?
    ) -> RequestExecutionFailure? {
        guard let afError else { return nil }

        // Alamofire can surface both a response and an error when the transfer
        // fails after headers arrive. Preserve URLSession-style semantics by
        // preferring transport and cancellation errors over any partial payload.
        if let transportErr = extractAlamofireTransportError(from: afError) {
            if isCancellation(transportErr) {
                return RequestExecutionFailure(
                    underlyingError: CancellationError(),
                    response: response,
                    responseBody: responseBody
                )
            }
            return RequestExecutionFailure(
                underlyingError: LLMError.networkError(underlying: transportErr),
                response: response,
                responseBody: responseBody
            )
        }

        // If we already have an HTTP response and there was no transport
        // failure, raw/status handling remains under NetworkManager's control.
        guard response == nil else { return nil }

        if isCancellation(afError) {
            return RequestExecutionFailure(
                underlyingError: CancellationError(),
                response: nil,
                responseBody: responseBody
            )
        }

        return RequestExecutionFailure(
            underlyingError: LLMError.networkError(underlying: afError.underlyingError ?? afError),
            response: nil,
            responseBody: responseBody
        )
    }

    nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let afError = error as? AFError, case .explicitlyCancelled = afError { return true }
        return false
    }

    /// Parse HTTP error into LLMError
    nonisolated func parseHTTPError(statusCode: Int, data: Data, headers: [AnyHashable: Any]) throws -> LLMError {
        switch statusCode {
        case 401:
            let message = providerErrorMessage(from: data)
                ?? normalizedTrimmedString(String(data: data, encoding: .utf8))
                    .map { String($0.prefix(2000)) }
            return .authenticationFailed(message: message)
        case 429:
            let retryAfter = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            let providerMessage = providerErrorMessage(from: data)
            return .rateLimitExceeded(
                retryAfter: retryAfter,
                providerMessage: providerMessage,
                fastModeExhausted: hasFastModeHeader(in: headers)
            )
        default:
            let message = providerErrorMessage(from: data)
                ?? normalizedTrimmedString(String(data: data, encoding: .utf8))
                    .map { String($0.prefix(2000)) }
                ?? "Unknown error"
            return .providerError(code: "\(statusCode)", message: message)
        }
    }

    /// Extract `error.message` from a JSON error body. Matches the shape used by
    /// Anthropic and OpenAI-compatible providers: `{"error": {"message": "..."}}`.
    /// Returns `nil` if the body isn't JSON in that shape.
    nonisolated func providerErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any],
              let errorObj = dict["error"] as? [String: Any],
              let message = errorObj["message"] as? String,
              let trimmed = message.trimmedNonEmpty else {
            return nil
        }
        return String(trimmed.prefix(2000))
    }

    /// `true` when any response header key starts with `anthropic-fast-`, which
    /// Anthropic includes on 429s tied to fast mode's dedicated rate-limit pool.
    nonisolated func hasFastModeHeader(in headers: [AnyHashable: Any]) -> Bool {
        for key in headers.keys {
            if let name = (key as? String)?.lowercased(),
               name.hasPrefix("anthropic-fast-") {
                return true
            }
        }
        return false
    }
}
