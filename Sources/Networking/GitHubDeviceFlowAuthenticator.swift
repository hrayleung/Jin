import Foundation

actor GitHubDeviceFlowAuthenticator {
    static let authModeHint = "github.oauth.device.v1"

    private let networkManager: NetworkManager
    private let gitHubAPIVersion = "2022-11-28"

    init(networkManager: NetworkManager = NetworkManager()) {
        self.networkManager = networkManager
    }

    func requestDeviceCode(clientID: String) async throws -> GitHubDeviceCodeResponse {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw GitHubDeviceFlowError.missingClientID
        }

        var request = URLRequest(url: try validatedURL("https://github.com/login/device/code"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addValue(jinUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formEncodedBody([
            "client_id": normalizedClientID
        ])

        let (data, _) = try await networkManager.sendRequest(request)
        return try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: data)
    }

    func waitForAccessToken(
        clientID: String,
        deviceCodeResponse: GitHubDeviceCodeResponse
    ) async throws -> GitHubDeviceAccessToken {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw GitHubDeviceFlowError.missingClientID
        }

        let deadline = Date().addingTimeInterval(TimeInterval(deviceCodeResponse.expiresIn))
        var pollIntervalSeconds = max(5, deviceCodeResponse.interval)

        try await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds) * 1_000_000_000)

        while Date() < deadline {
            try Task.checkCancellation()

            let response = try await requestAccessToken(
                clientID: normalizedClientID,
                deviceCode: deviceCodeResponse.deviceCode
            )

            switch response {
            case .authorized(let token):
                return token
            case .authorizationPending:
                break
            case .slowDown:
                pollIntervalSeconds += 5
            case .accessDenied:
                throw GitHubDeviceFlowError.accessDenied
            case .expiredToken:
                throw GitHubDeviceFlowError.expiredToken
            case .unsupported(let error):
                throw error
            }

            try await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds) * 1_000_000_000)
        }

        throw GitHubDeviceFlowError.expiredToken
    }

    func validateGitHubModelsAccess(accessToken: String) async throws {
        var request = URLRequest(url: try validatedURL("https://models.github.ai/catalog/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue(gitHubAPIVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.addValue(jinUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            _ = try await networkManager.sendRequest(request)
        } catch let llmError as LLMError {
            switch llmError {
            case .authenticationFailed, .providerError, .rateLimitExceeded:
                throw GitHubDeviceFlowError.missingModelsAccess(underlying: llmError)
            default:
                throw llmError
            }
        }
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        var request = URLRequest(url: try validatedURL("https://api.github.com/user"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue(gitHubAPIVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.addValue(jinUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await networkManager.sendRequest(request)
        return try JSONDecoder().decode(GitHubAuthenticatedUser.self, from: data)
    }

    private func requestAccessToken(
        clientID: String,
        deviceCode: String
    ) async throws -> GitHubDeviceAccessTokenPollResult {
        var request = URLRequest(url: try validatedURL("https://github.com/login/oauth/access_token"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addValue(jinUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formEncodedBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        let (data, _) = try await networkManager.sendRawRequest(request)

        if let token = try? JSONDecoder().decode(GitHubDeviceAccessToken.self, from: data),
           !token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .authorized(token)
        }

        let errorResponse = try JSONDecoder().decode(GitHubDeviceFlowErrorResponse.self, from: data)
        switch errorResponse.error {
        case "authorization_pending":
            return .authorizationPending
        case "slow_down":
            return .slowDown
        case "access_denied":
            return .accessDenied
        case "expired_token":
            return .expiredToken
        default:
            return .unsupported(
                GitHubDeviceFlowError.unexpectedResponse(
                    message: errorResponse.errorDescription ?? errorResponse.error
                )
            )
        }
    }

    private func formEncodedBody(_ parameters: [String: String]) -> Data? {
        let encoded = parameters.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }
        .sorted()
        .joined(separator: "&")

        return Data(encoded.utf8)
    }

    private func urlEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

struct GitHubDeviceCodeResponse: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct GitHubDeviceAccessToken: Decodable, Equatable {
    let accessToken: String
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

struct GitHubAuthenticatedUser: Decodable, Equatable {
    let login: String
    let name: String?
    let email: String?
}

private struct GitHubDeviceFlowErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private enum GitHubDeviceAccessTokenPollResult {
    case authorized(GitHubDeviceAccessToken)
    case authorizationPending
    case slowDown
    case accessDenied
    case expiredToken
    case unsupported(GitHubDeviceFlowError)
}

enum GitHubDeviceFlowError: Error, LocalizedError {
    case missingClientID
    case accessDenied
    case expiredToken
    case missingModelsAccess(underlying: LLMError)
    case unexpectedResponse(message: String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "GitHub OAuth App Client ID is required."
        case .accessDenied:
            return "GitHub authorization was denied."
        case .expiredToken:
            return "GitHub device authorization expired before completion."
        case .missingModelsAccess(let underlying):
            return "GitHub login succeeded, but this token cannot access GitHub Models. Use a PAT with the `models` scope or a token that can call the Models API.\n\n\(underlying.localizedDescription)"
        case .unexpectedResponse(let message):
            return "GitHub OAuth returned an unexpected response: \(message)"
        }
    }
}
