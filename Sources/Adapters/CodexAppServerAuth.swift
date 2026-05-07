import Foundation

// MARK: - Public Account Methods

extension CodexAppServerAdapter {
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
        guard let trimmed = Self.trimmedValue(loginID) else { return }

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
        guard let trimmed = Self.trimmedValue(loginID) else {
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
}
