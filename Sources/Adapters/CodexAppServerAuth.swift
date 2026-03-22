import Foundation

// MARK: - Authentication & Session Initialization

extension CodexAppServerAdapter {

    // MARK: - Public Account Methods

    func readAccountStatus(refreshToken: Bool = false) async throws -> AccountStatus {
        try await withInitializedClient { client in
            try await readAccountStatus(using: client, refreshToken: refreshToken)
        }
    }

    func readPrimaryRateLimit() async throws -> RateLimitStatus? {
        try await withInitializedClient { client in
            try await authenticateSession(client)

            let result = try await requestWithServerRequestHandling(
                client: client,
                method: "account/rateLimits/read",
                params: nil
            )

            return parsePrimaryRateLimit(from: result)
        }
    }

    func startChatGPTLogin() async throws -> ChatGPTLoginChallenge {
        try await withInitializedClient { client in
            let result = try await requestWithServerRequestHandling(
                client: client,
                method: "account/login/start",
                params: ["type": "chatgpt"]
            )

            guard let object = result.objectValue else {
                throw LLMError.decodingError(message: "Codex account/login/start returned unexpected payload.")
            }

            guard let loginID = object.string(at: ["loginId"]), !loginID.isEmpty else {
                throw LLMError.decodingError(message: "Codex account/login/start did not return loginId.")
            }
            guard let authURLString = object.string(at: ["authUrl"]),
                  let authURL = URL(string: authURLString) else {
                throw LLMError.decodingError(message: "Codex account/login/start did not return a valid authUrl.")
            }

            return ChatGPTLoginChallenge(loginID: loginID, authURL: authURL)
        }
    }

    func cancelChatGPTLogin(loginID: String) async throws {
        let trimmed = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        _ = try await withInitializedClient { client in
            try await requestWithServerRequestHandling(
                client: client,
                method: "account/login/cancel",
                params: ["loginId": trimmed]
            )
        }
    }

    func waitForChatGPTLoginCompletion(
        loginID: String,
        timeoutSeconds: Int = 180
    ) async throws -> AccountStatus {
        let trimmed = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.invalidRequest(message: "Codex loginId is empty.")
        }

        return try await withInitializedClient { client in
            let timeout = max(timeoutSeconds, 1)
            let deadline = Date().addingTimeInterval(TimeInterval(timeout))

            while Date() < deadline {
                try Task.checkCancellation()
                let status = try await readAccountStatus(using: client, refreshToken: true)
                if status.isAuthenticated {
                    return status
                }

                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            _ = try? await requestWithServerRequestHandling(
                client: client,
                method: "account/login/cancel",
                params: ["loginId": trimmed]
            )
            throw LLMError.authenticationFailed(message: "Timed out waiting for ChatGPT login. Please try again.")
        }
    }

    func logoutAccount() async throws {
        _ = try await withInitializedClient { client in
            try await requestWithServerRequestHandling(
                client: client,
                method: "account/logout",
                params: nil
            )
        }
    }

    // MARK: - Session Lifecycle

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
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
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

    // MARK: - Auth Parsing Helpers

    func parseAccountStatus(from result: JSONValue) throws -> AccountStatus {
        guard let object = result.objectValue else {
            throw LLMError.decodingError(message: "Codex account/read returned unexpected payload.")
        }

        let authMode = object.string(at: ["authMode"])
        let requiresOpenAIAuth = object.bool(at: ["requiresOpenaiAuth"])
            ?? object.bool(at: ["requiresOpenAIAuth"])
            ?? false
        let account = object.object(at: ["account"])

        let accountType = account?.string(at: ["type"]) ?? authMode
        let displayName = account?.string(at: ["name"])
            ?? account?.string(at: ["displayName"])
            ?? account?.string(at: ["username"])
        let email = account?.string(at: ["email"])

        return AccountStatus(
            isAuthenticated: account != nil,
            requiresOpenAIAuth: requiresOpenAIAuth,
            authMode: authMode,
            accountType: accountType,
            displayName: displayName,
            email: email
        )
    }

    func parsePrimaryRateLimit(from result: JSONValue) -> RateLimitStatus? {
        guard let object = result.objectValue else { return nil }

        let rootRateLimit = object.object(at: ["rateLimit"])
            ?? object.object(at: ["primary"])
            ?? object.object(at: ["rateLimits", "primary"])
        let arrayRateLimit = object.array(at: ["rateLimits"])?.first?.objectValue
            ?? object.array(at: ["limits"])?.first?.objectValue
        guard let rateLimit = rootRateLimit ?? arrayRateLimit else {
            return nil
        }

        let name = rateLimit.string(at: ["name"])
            ?? rateLimit.string(at: ["id"])
            ?? "primary"
        let usedPercentage = rateLimit.double(at: ["usedPercentage"])
            ?? rateLimit.double(at: ["usedPercent"])
            ?? rateLimit.double(at: ["percentUsed"])
        let windowMinutes = rateLimit.int(at: ["windowMinutes"])
            ?? rateLimit.int(at: ["windowMins"])
        let resetsAt = parseDate(rateLimit.string(at: ["resetsAt"])
            ?? rateLimit.string(at: ["resetAt"])
            ?? rateLimit.string(at: ["resetTime"]))

        return RateLimitStatus(
            name: name,
            usedPercentage: usedPercentage,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }

        let fallback = ISO8601DateFormatter()
        return fallback.date(from: raw)
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
