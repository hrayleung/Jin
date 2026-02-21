import Foundation
import Network

/// JSON-RPC client over WebSocket for communicating with Codex App Server.
actor CodexWebSocketRPCClient {
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resumeOnce {
                        continuation.resume()
                    }
                case .failed(let error):
                    gate.resumeOnce {
                        continuation.resume(throwing: LLMError.networkError(underlying: error))
                    }
                case .cancelled:
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

// MARK: - Stream State

final class CodexStreamState: @unchecked Sendable {
    var didEmitMessageStart = false
    var didEmitAssistantText = false
    var didEmitMessageEnd = false
    var didCompleteTurn = false
    var activeTurnID: String?
    var latestUsage: Usage?
}

// MARK: - Continuation Resume Gate

final class ContinuationResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        action()
    }
}

// MARK: - JSONRPC ID Helpers

extension JSONRPCID {
    var rawValue: Any {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return value
        }
    }
}

// MARK: - JSONValue Convenience Accessors

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let number) = self else { return nil }
        return Int(number)
    }

    var doubleValue: Double? {
        guard case .number(let number) = self else { return nil }
        return number
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

// MARK: - JSONValue Dictionary Path Access

extension Dictionary where Key == String, Value == JSONValue {
    func string(at path: [String]) -> String? {
        value(at: path)?.stringValue
    }

    func int(at path: [String]) -> Int? {
        value(at: path)?.intValue
    }

    func double(at path: [String]) -> Double? {
        value(at: path)?.doubleValue
    }

    func bool(at path: [String]) -> Bool? {
        value(at: path)?.boolValue
    }

    func object(at path: [String]) -> [String: JSONValue]? {
        value(at: path)?.objectValue
    }

    func array(at path: [String]) -> [JSONValue]? {
        value(at: path)?.arrayValue
    }

    func contains(inArray expected: String, at path: [String]) -> Bool {
        guard let values = array(at: path) else { return false }
        return values.contains { $0.stringValue?.lowercased() == expected.lowercased() }
    }

    private func value(at path: [String]) -> JSONValue? {
        guard !path.isEmpty else { return .object(self) }
        var current: JSONValue = .object(self)

        for key in path {
            guard case .object(let object) = current,
                  let next = object[key] else {
                return nil
            }
            current = next
        }

        return current
    }
}
