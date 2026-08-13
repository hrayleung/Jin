import Foundation

enum MCPOAuthError: Error, LocalizedError, Equatable {
    case missingEndpoint
    case discoveryFailed(String)
    case registrationFailed(String)
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case notAuthenticated
    case cancelled
    case invalidCallback
    case stateMismatch
    case browserUnavailable

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Enter an MCP endpoint URL before signing in."
        case .discoveryFailed(let message):
            return "Couldn’t discover how to sign in.\n\n\(message)"
        case .registrationFailed(let message):
            return "This server doesn’t support automatic browser sign-in.\n\n\(message)\n\nUse a token or API key instead."
        case .authorizationFailed(let message):
            return "Sign-in was refused.\n\n\(message)"
        case .tokenExchangeFailed(let message):
            return "Couldn’t finish sign-in.\n\n\(message)"
        case .notAuthenticated:
            return "Sign in with your browser first. Open the server in Settings and choose Sign in."
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidCallback:
            return "The sign-in page returned an incomplete response."
        case .stateMismatch:
            return "Sign-in could not be verified. Try again."
        case .browserUnavailable:
            return "Jin couldn’t open a browser to sign in."
        }
    }
}

struct MCPOAuthProtectedResourceMetadata: Decodable, Equatable, Sendable {
    let resource: String?
    let authorizationServers: [URL]
    let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resource = try container.decodeIfPresent(String.self, forKey: .resource)
        let rawServers = try container.decodeIfPresent([String].self, forKey: .authorizationServers) ?? []
        authorizationServers = rawServers.compactMap(URL.init(string:))
        scopesSupported = try container.decodeIfPresent([String].self, forKey: .scopesSupported)
    }
}

struct MCPOAuthAuthorizationServerMetadata: Decodable, Equatable, Sendable {
    let issuer: String?
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let scopesSupported: [String]?
    let codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}

struct MCPOAuthClientRegistration: Decodable, Equatable, Sendable {
    let clientID: String
    let clientSecret: String?
    let tokenEndpointAuthMethod: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    }
}

struct MCPOAuthTokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct MCPOAuthStoredSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var expiresAt: Date?
    var scope: String?
    var clientID: String
    var clientSecret: String?
    var tokenEndpoint: URL
    var authorizationEndpoint: URL?
    var resource: String

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

enum MCPOAuthConstants {
    static let callbackScheme = "jin-mcp"
    static let redirectURI = "jin-mcp://oauth"
    static let clientName = "Jin"
}
