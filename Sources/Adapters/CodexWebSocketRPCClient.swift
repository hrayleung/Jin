import Foundation
import Network

/// JSON-RPC client over WebSocket for communicating with Codex App Server.
actor CodexWebSocketRPCClient {
    private static let connectTimeoutSeconds: TimeInterval = 8

    private let url: URL
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "jin.codex.websocket")
    private var nextRequestID = 1
    private let decoder = JSONDecoder()

    init(url: URL) {
        self.url = url
    }

    func connect() async throws {
        guard connection == nil else { return }

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let tlsOptions: NWProtocolTLS.Options? = url.scheme == "wss" ? NWProtocolTLS.Options() : nil
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let connection = NWConnection(to: .url(url), using: parameters)
        self.connection = connection

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ContinuationResumeGate()
                let timeout = DispatchWorkItem {
                    gate.resumeOnce {
                        // Keep timeout scoped strictly to the connect phase.
                        connection.cancel()
                        continuation.resume(
                            throwing: LLMError.networkError(
                                underlying: NSError(
                                    domain: "CodexWebSocket",
                                    code: Int(ETIMEDOUT),
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "Connection timed out while connecting to Codex App Server."
                                    ]
                                )
                            )
                        )
                    }
                }
                queue.asyncAfter(
                    deadline: .now() + Self.connectTimeoutSeconds,
                    execute: timeout
                )

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        timeout.cancel()
                        gate.resumeOnce {
                            continuation.resume()
                        }
                    case .failed(let error):
                        timeout.cancel()
                        Task { await self.clearConnectionIfCurrent(connection) }
                        gate.resumeOnce {
                            continuation.resume(throwing: LLMError.networkError(underlying: error))
                        }
                    case .cancelled:
                        timeout.cancel()
                        Task { await self.clearConnectionIfCurrent(connection) }
                        gate.resumeOnce {
                            continuation.resume(
                                throwing: LLMError.networkError(
                                    underlying: NSError(
                                        domain: "CodexWebSocket",
                                        code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "WebSocket connection was cancelled."]
                                    )
                                )
                            )
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } catch {
            connection.cancel()
            self.connection = nil
            throw error
        }
    }

    private func clearConnectionIfCurrent(_ candidate: NWConnection) {
        if let current = connection, current === candidate {
            connection = nil
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
    }

    func notify(method: String, params: [String: Any]?) async throws {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params {
            payload["params"] = params
        }
        try await send(payload)
    }

    func request(
        method: String,
        params: [String: Any]?,
        onInterleavedMessage: ((JSONRPCEnvelope) async throws -> Void)? = nil
    ) async throws -> JSONValue {
        let id = nextRequestID
        nextRequestID += 1

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params {
            payload["params"] = params
        }
        try await send(payload)

        while true {
            let envelope = try await receiveEnvelope()
            if envelope.id?.intValue == id, envelope.method == nil {
                if let error = envelope.error {
                    throw LLMError.providerError(
                        code: "\(error.code ?? -1)",
                        message: error.message
                    )
                }
                return envelope.result ?? .object([:])
            }
            try await onInterleavedMessage?(envelope)
        }
    }

    func respond(id: JSONRPCID, result: Any?) async throws {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.rawValue,
            "result": result ?? NSNull()
        ]
        if payload["id"] == nil {
            payload["id"] = NSNull()
        }
        try await send(payload)
    }

    func respondWithError(id: JSONRPCID, code: Int, message: String) async throws {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.rawValue,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if payload["id"] == nil {
            payload["id"] = NSNull()
        }
        try await send(payload)
    }

    func receiveEnvelope() async throws -> JSONRPCEnvelope {
        guard let connection else {
            throw LLMError.invalidRequest(message: "Codex socket is not connected.")
        }

        let data: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receiveMessage { data, _, _, error in
                if let error {
                    continuation.resume(throwing: LLMError.networkError(underlying: error))
                    return
                }
                guard let data else {
                    continuation.resume(
                        throwing: LLMError.networkError(
                            underlying: NSError(
                                domain: "CodexWebSocket",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Codex WebSocket connection closed."]
                            )
                        )
                    )
                    return
                }
                continuation.resume(returning: data)
            }
        }

        do {
            return try decoder.decode(JSONRPCEnvelope.self, from: data)
        } catch {
            throw LLMError.decodingError(message: "Invalid Codex JSON-RPC envelope: \(error.localizedDescription)")
        }
    }

    private func send(_ payload: [String: Any]) async throws {
        guard let connection else {
            throw LLMError.invalidRequest(message: "Codex socket is not connected.")
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "jsonrpc", metadata: [metadata])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: LLMError.networkError(underlying: error))
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
