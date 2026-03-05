import Foundation

/// Network manager for HTTP requests with streaming support
actor NetworkManager {
    private let overrideSession: URLSession?

    init(urlSession: URLSession? = nil) {
        self.overrideSession = urlSession
    }

    /// Resolves the URLSession to use for each request.
    /// When an explicit session is provided, it's always used.
    /// Otherwise, uses the shared URLSession.
    private var urlSession: URLSession {
        overrideSession ?? .shared
    }

    /// Stream request with custom parser
    func streamRequest<P: StreamParser>(
        _ request: URLRequest,
        parser: P
    ) -> AsyncThrowingStream<P.Event, Error> {
        var parserCopy = parser

        return AsyncThrowingStream { continuation in
            let task = Task {
                let requestID = await NetworkDebugLogger.shared.beginRequest(request, mode: "stream")
                var didLogResult = false
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        let error = LLMError.networkError(underlying: URLError(.badServerResponse))
                        await NetworkDebugLogger.shared.endRequest(
                            requestID: requestID,
                            response: nil,
                            responseBody: nil,
                            responseBodyTruncated: false,
                            error: error
                        )
                        didLogResult = true
                        throw error
                    }

                    // Check for HTTP errors
                    if httpResponse.statusCode >= 400 {
                        let errorData = try await bytes.reduce(into: Data()) { data, byte in
                            data.append(byte)
                        }
                        let parsedError = try parseHTTPError(
                            statusCode: httpResponse.statusCode,
                            data: errorData,
                            headers: httpResponse.allHeaderFields
                        )
                        await NetworkDebugLogger.shared.endRequest(
                            requestID: requestID,
                            response: httpResponse,
                            responseBody: errorData,
                            responseBodyTruncated: false,
                            error: parsedError
                        )
                        didLogResult = true
                        throw parsedError
                    }

                    var capturedResponseData = Data()

                    for try await byte in bytes {
                        capturedResponseData.append(byte)

                        parserCopy.append(byte)
                        while let event = parserCopy.nextEvent() {
                            continuation.yield(event)
                        }
                    }

                    await NetworkDebugLogger.shared.endRequest(
                        requestID: requestID,
                        response: httpResponse,
                        responseBody: capturedResponseData,
                        responseBodyTruncated: false,
                        error: nil
                    )
                    didLogResult = true
                    continuation.finish()
                } catch {
                    if !didLogResult {
                        await NetworkDebugLogger.shared.endRequest(
                            requestID: requestID,
                            response: nil,
                            responseBody: nil,
                            responseBodyTruncated: false,
                            error: error
                        )
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Non-streaming request
    func sendRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let requestID = await NetworkDebugLogger.shared.beginRequest(request, mode: "data")
        var didLogResult = false
        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = LLMError.networkError(underlying: URLError(.badServerResponse))
                await NetworkDebugLogger.shared.endRequest(
                    requestID: requestID,
                    response: nil,
                    responseBody: nil,
                    responseBodyTruncated: false,
                    error: error
                )
                didLogResult = true
                throw error
            }

            if httpResponse.statusCode >= 400 {
                let parsedError = try parseHTTPError(statusCode: httpResponse.statusCode, data: data, headers: httpResponse.allHeaderFields)
                await NetworkDebugLogger.shared.endRequest(
                    requestID: requestID,
                    response: httpResponse,
                    responseBody: data,
                    responseBodyTruncated: false,
                    error: parsedError
                )
                didLogResult = true
                throw parsedError
            }

            await NetworkDebugLogger.shared.endRequest(
                requestID: requestID,
                response: httpResponse,
                responseBody: data,
                responseBodyTruncated: false,
                error: nil
            )
            didLogResult = true

            return (data, httpResponse)
        } catch {
            if !didLogResult {
                await NetworkDebugLogger.shared.endRequest(
                    requestID: requestID,
                    response: nil,
                    responseBody: nil,
                    responseBodyTruncated: false,
                    error: error
                )
            }
            throw error
        }
    }

    /// Non-streaming request that returns the response regardless of HTTP status code.
    /// Use this for polling endpoints where non-2xx responses carry meaningful status information.
    func sendRawRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let requestID = await NetworkDebugLogger.shared.beginRequest(request, mode: "raw")
        var didLogResult = false
        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = LLMError.networkError(underlying: URLError(.badServerResponse))
                await NetworkDebugLogger.shared.endRequest(
                    requestID: requestID,
                    response: nil,
                    responseBody: nil,
                    responseBodyTruncated: false,
                    error: error
                )
                didLogResult = true
                throw error
            }

            await NetworkDebugLogger.shared.endRequest(
                requestID: requestID,
                response: httpResponse,
                responseBody: data,
                responseBodyTruncated: false,
                error: nil
            )
            didLogResult = true
            return (data, httpResponse)
        } catch {
            if !didLogResult {
                await NetworkDebugLogger.shared.endRequest(
                    requestID: requestID,
                    response: nil,
                    responseBody: nil,
                    responseBodyTruncated: false,
                    error: error
                )
            }
            throw error
        }
    }

    /// Parse HTTP error into LLMError
    private func parseHTTPError(statusCode: Int, data: Data, headers: [AnyHashable: Any]) throws -> LLMError {
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
