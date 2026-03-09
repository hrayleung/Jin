import Foundation
import Alamofire

/// Network manager for HTTP requests with streaming support
actor NetworkManager {
    nonisolated static let defaultRequestTimeoutInterval: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let defaultResourceTimeoutInterval: TimeInterval = 7 * 24 * 60 * 60

    private enum HTTPErrorDisposition {
        case failOnErrorStatus
        case allowAnyStatus
    }

    private struct RequestExecutionFailure: Error {
        let underlyingError: Error
        let response: HTTPURLResponse?
        let responseBody: Data?
    }

    private static let defaultSession: Session = {
        makeSession(configuration: makeDefaultSessionConfiguration())
    }()

    /// Shared Alamofire session for one-shot and streaming requests.
    ///
    /// The session is configured once so request interception, event monitoring,
    /// and transport behavior remain consistent across every request mode.
    private let session: Session

    init(
        configuration: URLSessionConfiguration? = nil,
        interceptor: (any RequestInterceptor)? = nil,
        eventMonitors: [any EventMonitor] = []
    ) {
        if configuration == nil, interceptor == nil, eventMonitors.isEmpty {
            self.session = Self.defaultSession
        } else {
            self.session = Self.makeSession(
                configuration: configuration ?? Self.makeDefaultSessionConfiguration(),
                interceptor: interceptor,
                eventMonitors: eventMonitors
            )
        }
    }

    nonisolated static func makeDefaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = defaultRequestTimeoutInterval
        configuration.timeoutIntervalForResource = defaultResourceTimeoutInterval
        return configuration
    }

    private nonisolated static func makeSession(
        configuration: URLSessionConfiguration,
        interceptor: (any RequestInterceptor)? = nil,
        eventMonitors: [any EventMonitor] = []
    ) -> Session {
        let monitors = [AlamofireNotifications()] + eventMonitors
        let rootQueue = DispatchQueue(label: "jin.network.alamofire.root")
        let requestQueue = DispatchQueue(label: "jin.network.alamofire.request", target: rootQueue)
        let serializationQueue = DispatchQueue(label: "jin.network.alamofire.serialization", target: rootQueue)

        return Session(
            configuration: configuration,
            rootQueue: rootQueue,
            requestSetup: .lazy,
            requestQueue: requestQueue,
            serializationQueue: serializationQueue,
            interceptor: interceptor,
            eventMonitors: monitors
        )
    }

    /// Stream request with custom parser
    func streamRequest<P: StreamParser>(
        _ request: URLRequest,
        parser: P
    ) -> AsyncThrowingStream<P.Event, Error> {
        var parserCopy = parser

        return AsyncThrowingStream { continuation in
            let requestIDTask = Task {
                await NetworkDebugLogger.shared.beginRequest(request, mode: "stream")
            }
            let callbackQueue = DispatchQueue(label: "jin.network.stream.\(UUID().uuidString)")
            var didFinish = false
            var response: HTTPURLResponse?
            var capturedResponseData = Data()

            let dataStreamRequest = session.streamRequest(
                request,
                automaticallyCancelOnStreamError: false,
                shouldAutomaticallyResume: false
            )

            dataStreamRequest.onHTTPResponse(on: callbackQueue) { httpResponse, completionHandler in
                response = httpResponse
                completionHandler(.allow)
            }

            dataStreamRequest.responseStream(on: callbackQueue) { stream in
                guard !didFinish else { return }

                switch stream.event {
                case .stream(.success(let chunk)):
                    capturedResponseData.append(chunk)

                    guard let httpResponse = response, httpResponse.statusCode < 400 else { return }

                    for byte in chunk {
                        parserCopy.append(byte)
                        while let event = parserCopy.nextEvent() {
                            continuation.yield(event)
                        }
                    }

                case .complete(let completion):
                    didFinish = true
                    let finalResponse = completion.response ?? response
                    let responseBody = capturedResponseData.isEmpty ? nil : capturedResponseData

                    Task {
                        let requestID = await requestIDTask.value
                        let resolvedResult = self.resolveStreamCompletion(
                            completion: completion,
                            response: finalResponse,
                            responseBody: responseBody
                        )

                        switch resolvedResult {
                        case .success:
                            await NetworkDebugLogger.shared.endRequest(
                                requestID: requestID,
                                response: finalResponse,
                                responseBody: responseBody,
                                responseBodyTruncated: false,
                                error: nil
                            )
                            continuation.finish()

                        case .failure(let failure):
                            await NetworkDebugLogger.shared.endRequest(
                                requestID: requestID,
                                response: failure.response,
                                responseBody: failure.responseBody,
                                responseBodyTruncated: false,
                                error: failure.underlyingError
                            )
                            continuation.finish(throwing: failure.underlyingError)
                        }
                    }
                }
            }

            let startupTask = Task {
                _ = await requestIDTask.value
                dataStreamRequest.resume()
            }

            continuation.onTermination = { @Sendable _ in
                startupTask.cancel()
                requestIDTask.cancel()
                dataStreamRequest.cancel()
            }
        }
    }

    /// Non-streaming request
    func sendRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await executeDataRequest(
            request,
            mode: "data",
            httpErrorDisposition: .failOnErrorStatus
        )
    }

    /// Non-streaming request that returns the response regardless of HTTP status code.
    /// Use this for polling endpoints where non-2xx responses carry meaningful status information.
    func sendRawRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await executeDataRequest(
            request,
            mode: "raw",
            httpErrorDisposition: .allowAnyStatus
        )
    }

    private func executeDataRequest(
        _ request: URLRequest,
        mode: String,
        httpErrorDisposition: HTTPErrorDisposition
    ) async throws -> (Data, HTTPURLResponse) {
        let requestID = await NetworkDebugLogger.shared.beginRequest(request, mode: mode)
        do {
            let dataResponse = await makeDataRequest(for: request)
                .serializingData(automaticallyCancelling: true)
                .response

            let result = try resolveDataResponse(
                dataResponse,
                httpErrorDisposition: httpErrorDisposition
            )

            await NetworkDebugLogger.shared.endRequest(
                requestID: requestID,
                response: result.1,
                responseBody: result.0,
                responseBodyTruncated: false,
                error: nil
            )
            return result
        } catch let failure as RequestExecutionFailure {
            await NetworkDebugLogger.shared.endRequest(
                requestID: requestID,
                response: failure.response,
                responseBody: failure.responseBody,
                responseBodyTruncated: false,
                error: failure.underlyingError
            )
            throw failure.underlyingError
        }
    }

    private func resolveDataResponse(
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
            throw RequestExecutionFailure(
                underlyingError: LLMError.networkError(underlying: URLError(.badServerResponse)),
                response: nil,
                responseBody: nil
            )
        }

        if httpErrorDisposition == .failOnErrorStatus, httpResponse.statusCode >= 400 {
            throw RequestExecutionFailure(
                underlyingError: try parseHTTPError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    headers: httpResponse.allHeaderFields
                ),
                response: httpResponse,
                responseBody: data
            )
        }

        return (data, httpResponse)
    }

    private func makeDataRequest(for request: URLRequest) -> DataRequest {
        if let bodyStream = request.httpBodyStream {
            return session.upload(bodyStream, with: sanitizedUploadRequest(request))
        }

        return session.request(request)
    }

    private nonisolated func sanitizedUploadRequest(_ request: URLRequest) -> URLRequest {
        var uploadRequest = request
        uploadRequest.httpBody = nil
        uploadRequest.httpBodyStream = nil
        return uploadRequest
    }

    private nonisolated func resolveStreamCompletion(
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
            return .failure(
                RequestExecutionFailure(
                    underlyingError: LLMError.networkError(underlying: URLError(.badServerResponse)),
                    response: nil,
                    responseBody: nil
                )
            )
        }

        if httpResponse.statusCode >= 400 {
            do {
                let parsedError = try parseHTTPError(
                    statusCode: httpResponse.statusCode,
                    data: responseBody ?? Data(),
                    headers: httpResponse.allHeaderFields
                )
                return .failure(
                    RequestExecutionFailure(
                        underlyingError: parsedError,
                        response: httpResponse,
                        responseBody: responseBody
                    )
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

    private nonisolated func resolvedRequestExecutionFailure(
        from afError: AFError?,
        response: HTTPURLResponse?,
        responseBody: Data?
    ) -> RequestExecutionFailure? {
        guard let afError else { return nil }

        // Alamofire can surface both a response and an error when the transfer
        // fails after headers arrive. Preserve URLSession-style semantics by
        // preferring transport and cancellation errors over any partial payload.
        if let transportErr = extractTransportError(from: afError) {
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

    /// Extracts the underlying error from an AFError if it represents a transport-level
    /// failure (task failed, session invalidated/deinitialized, or explicit cancellation).
    /// Returns nil for non-transport errors (serialization, validation) which are safe to
    /// ignore since we handle HTTP status codes and raw data ourselves.
    private nonisolated func extractTransportError(from afError: AFError?) -> Error? {
        guard let afError else { return nil }
        switch afError {
        case .sessionTaskFailed(let error):
            return error
        case .sessionInvalidated(let error):
            return error ?? afError
        case .sessionDeinitialized:
            return afError
        case .explicitlyCancelled:
            return afError
        case .requestRetryFailed(_, let originalError):
            if let afOriginal = originalError as? AFError {
                return extractTransportError(from: afOriginal)
            }
            return originalError
        case .createURLRequestFailed,
             .invalidURL,
             .multipartEncodingFailed,
             .parameterEncodingFailed,
             .parameterEncoderFailed,
             .requestAdaptationFailed,
             .responseSerializationFailed,
             .responseValidationFailed,
             .urlRequestValidationFailed:
            return nil
        #if canImport(Security)
        case .serverTrustEvaluationFailed:
            return afError
        #endif
        case .createUploadableFailed,
             .downloadedFileMoveFailed:
            return nil
        @unknown default:
            return nil
        }
    }

    private nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let afError = error as? AFError, case .explicitlyCancelled = afError { return true }
        return false
    }

    /// Parse HTTP error into LLMError
    private nonisolated func parseHTTPError(statusCode: Int, data: Data, headers: [AnyHashable: Any]) throws -> LLMError {
        switch statusCode {
        case 401:
            let message = normalizedTrimmedString(String(data: data, encoding: .utf8))
                .map { String($0.prefix(2000)) }
            return .authenticationFailed(message: message)
        case 429:
            let retryAfter = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            return .rateLimitExceeded(retryAfter: retryAfter)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            return .providerError(code: "\(statusCode)", message: message)
        }
    }
}

/// Stream parser protocol
protocol StreamParser: Sendable {
    associatedtype Event: Sendable
    mutating func append(_ byte: UInt8)
    mutating func nextEvent() -> Event?
}

/// Streaming task manager for cancellation
actor StreamingTaskManager {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    func register(id: UUID, task: Task<Void, Never>) {
        activeTasks[id] = task
    }

    func cancel(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
