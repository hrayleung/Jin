import Foundation

/// Network manager for HTTP requests with streaming support
actor NetworkManager {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Stream request with custom parser
    func streamRequest<P: StreamParser>(
        _ request: URLRequest,
        parser: P
    ) -> AsyncThrowingStream<P.Event, Error> {
        var parserCopy = parser

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.networkError(underlying: URLError(.badServerResponse))
                    }

                    // Check for HTTP errors
                    if httpResponse.statusCode >= 400 {
                        let errorData = try await bytes.reduce(into: Data()) { data, byte in
                            data.append(byte)
                        }
                        throw try parseHTTPError(statusCode: httpResponse.statusCode, data: errorData, headers: httpResponse.allHeaderFields)
                    }

                    for try await byte in bytes {
                        parserCopy.append(byte)
                        while let event = parserCopy.nextEvent() {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
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
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(underlying: URLError(.badServerResponse))
        }

        if httpResponse.statusCode >= 400 {
            throw try parseHTTPError(statusCode: httpResponse.statusCode, data: data, headers: httpResponse.allHeaderFields)
        }

        return (data, httpResponse)
    }

    /// Parse HTTP error into LLMError
    private func parseHTTPError(statusCode: Int, data: Data, headers: [AnyHashable: Any]) throws -> LLMError {
        switch statusCode {
        case 401:
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = (message?.isEmpty == false) ? message : nil
            let limited = trimmed.map { String($0.prefix(2000)) }
            return .authenticationFailed(message: limited)
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
protocol StreamParser {
    associatedtype Event
    mutating func append(_ byte: UInt8)
    mutating func nextEvent() -> Event?
}

/// Retry manager with exponential backoff
actor RetryManager {
    private let maxAttempts: Int
    private let baseDelay: TimeInterval

    init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    func withRetry<T>(
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                return try await operation()
            } catch let error as LLMError {
                lastError = error

                // Don't retry certain errors
                switch error {
                case .authenticationFailed, .invalidRequest, .contentFiltered:
                    throw error
                case .rateLimitExceeded(let retryAfter):
                    if let retryAfter {
                        try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                        attempt += 1
                        continue
                    }
                default:
                    break
                }

                // Exponential backoff
                let delay = min(baseDelay * pow(2.0, Double(attempt)), 60.0)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            } catch {
                lastError = error
                let delay = min(baseDelay * pow(2.0, Double(attempt)), 60.0)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }

        throw lastError ?? LLMError.networkError(underlying: URLError(.unknown))
    }
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
