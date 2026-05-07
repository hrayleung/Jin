import Foundation

extension CodexAppServerAdapter {
    func withInitializedClient<T>(
        _ body: (CodexWebSocketRPCClient) async throws -> T
    ) async throws -> T {
        let endpoint = try resolvedEndpointURL()
        let client = CodexWebSocketRPCClient(url: endpoint)
        do {
            try await client.connect()
            defer {
                Task { await client.close() }
            }
            try await initializeSession(with: client)
            return try await body(client)
        } catch {
            throw Self.remapCodexConnectivityError(error, endpoint: endpoint)
        }
    }

    func initializeSession(with client: CodexWebSocketRPCClient) async throws {
        _ = try await requestWithServerRequestHandling(
            client: client,
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "Jin",
                    "version": "0.1.0"
                ],
                "capabilities": NSNull()
            ]
        )
        try await client.notify(method: "initialized", params: nil)
    }

    func requestWithServerRequestHandling(
        client: CodexWebSocketRPCClient,
        method: String,
        params: [String: Any]?
    ) async throws -> JSONValue {
        try await client.request(method: method, params: params) { envelope in
            guard let requestID = envelope.id,
                  let requestMethod = envelope.method else {
                return
            }

            try await self.handleServerRequest(
                id: requestID,
                method: requestMethod,
                params: envelope.params?.objectValue,
                with: client,
                continuation: nil
            )
        }
    }

    func authenticateSession(_ client: CodexWebSocketRPCClient) async throws {
        if let trimmedAPIKey = Self.trimmedValue(apiKey) {
            try await authenticateWithAPIKey(trimmedAPIKey, client: client)
            return
        }

        let status = try await readAccountStatus(using: client, refreshToken: false)
        guard status.isAuthenticated else {
            throw LLMError.authenticationFailed(
                message: "Codex App Server is not logged in to ChatGPT. Open provider settings and connect your ChatGPT account."
            )
        }
    }

    func authenticateWithAPIKey(_ key: String, client: CodexWebSocketRPCClient) async throws {
        do {
            _ = try await requestWithServerRequestHandling(
                client: client,
                method: "account/login/start",
                params: [
                    "type": "apiKey",
                    "apiKey": key
                ]
            )
        } catch {
            guard shouldFallbackToLegacyLogin(error) else {
                throw error
            }
            _ = try await requestWithServerRequestHandling(
                client: client,
                method: "loginApiKey",
                params: ["apiKey": key]
            )
        }
    }

    func readAccountStatus(
        using client: CodexWebSocketRPCClient,
        refreshToken: Bool
    ) async throws -> AccountStatus {
        let result = try await requestWithServerRequestHandling(
            client: client,
            method: "account/read",
            params: ["refreshToken": refreshToken]
        )
        return try parseAccountStatus(from: result)
    }

    func shouldFallbackToLegacyLogin(_ error: Error) -> Bool {
        guard case let LLMError.providerError(code, message) = error else {
            return false
        }

        if code == "-32601" {
            return true
        }
        let lower = message.lowercased()
        return lower.contains("not found") || lower.contains("unknown method")
    }
}
