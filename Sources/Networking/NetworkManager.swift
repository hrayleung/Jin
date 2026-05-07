import Foundation
import Alamofire

/// Network manager for HTTP requests with streaming support
actor NetworkManager {
    nonisolated static let defaultRequestTimeoutInterval: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let defaultResourceTimeoutInterval: TimeInterval = 7 * 24 * 60 * 60

    private static let defaultSession: Session = {
        makeSession(configuration: makeDefaultSessionConfiguration())
    }()

    /// Shared session for one-shot and streaming requests.
    ///
    /// Configured once so interception, monitoring, and transport behavior
    /// remain consistent across every request mode.
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
        let monitors = eventMonitors
        let queueID = UUID().uuidString
        let rootQueue = DispatchQueue(label: "jin.network.alamofire.\(queueID).root")
        let requestQueue = DispatchQueue(label: "jin.network.alamofire.\(queueID).request", target: rootQueue)
        let serializationQueue = DispatchQueue(label: "jin.network.alamofire.\(queueID).serialization", target: rootQueue)

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

    /// Maximum bytes to capture from a stream response for error/logging purposes.
    /// Beyond this limit the body is truncated and flagged accordingly.
    private static let maxStreamCaptureBytes = 512 * 1024 // 512 KB

    /// Stream request with custom parser
    func streamRequest<P: StreamParser>(
        _ request: URLRequest,
        parser: P
    ) -> AsyncThrowingStream<P.Event, Error> {
        var parserCopy = parser
        let shouldCaptureSuccessBody = false
        let captureLimit = Self.maxStreamCaptureBytes

        return AsyncThrowingStream { continuation in
            let requestIDTask = Task {
                await NetworkDebugLogger.shared.beginRequest(request, mode: "stream")
            }
            let callbackQueue = DispatchQueue(label: "jin.network.stream.\(UUID().uuidString)")
            var didFinish = false
            var response: HTTPURLResponse?
            var capturedResponseData = Data()
            var responseBodyTruncated = false

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
                    let isError = response.map { $0.statusCode >= 400 } ?? false
                    let shouldCapture = isError || shouldCaptureSuccessBody

                    if shouldCapture, !responseBodyTruncated {
                        let remaining = captureLimit - capturedResponseData.count
                        if remaining > 0 {
                            let bytesToAppend = min(chunk.count, remaining)
                            capturedResponseData.append(chunk.prefix(bytesToAppend))
                            if bytesToAppend < chunk.count {
                                responseBodyTruncated = true
                            }
                        } else {
                            responseBodyTruncated = true
                        }
                    }

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
                    let wasTruncated = responseBodyTruncated

                    let resolvedResult = self.resolveStreamCompletion(
                        completion: completion,
                        response: finalResponse,
                        responseBody: responseBody
                    )

                    if case .success = resolvedResult {
                        parserCopy.finish()
                        while let event = parserCopy.nextEvent() {
                            continuation.yield(event)
                        }
                    }

                    Task {
                        let requestID = await requestIDTask.value

                        switch resolvedResult {
                        case .success:
                            await NetworkDebugLogger.shared.endRequest(
                                requestID: requestID,
                                response: finalResponse,
                                responseBody: Self.makeDebugLogResponseBody(
                                    responseBody,
                                    response: finalResponse,
                                    wasTruncated: wasTruncated
                                ),
                                responseBodyTruncated: wasTruncated,
                                error: nil
                            )
                            continuation.finish()

                        case .failure(let failure):
                            await NetworkDebugLogger.shared.endRequest(
                                requestID: requestID,
                                response: failure.response,
                                responseBody: Self.makeDebugLogResponseBody(
                                    failure.responseBody,
                                    response: failure.response,
                                    wasTruncated: wasTruncated
                                ),
                                responseBodyTruncated: wasTruncated,
                                error: failure.underlyingError
                            )
                            continuation.finish(throwing: failure.underlyingError)
                        }
                    }
                }
            }

            dataStreamRequest.resume()

            continuation.onTermination = { @Sendable _ in
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
                responseBody: Self.makeDebugLogResponseBody(
                    result.0,
                    response: result.1,
                    wasTruncated: false
                ),
                responseBodyTruncated: false,
                error: nil
            )
            return result
        } catch let failure as RequestExecutionFailure {
            await NetworkDebugLogger.shared.endRequest(
                requestID: requestID,
                response: failure.response,
                responseBody: Self.makeDebugLogResponseBody(
                    failure.responseBody,
                    response: failure.response,
                    wasTruncated: false
                ),
                responseBodyTruncated: false,
                error: failure.underlyingError
            )
            throw failure.underlyingError
        }
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
}
