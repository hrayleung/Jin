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

/// Previous custom-OAuth keychain payload. Kept so 0.12 tokens can be migrated
/// onto the SDK’s `OAuthAccessToken` shape.
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
}

enum MCPOAuthConstants {
    static let clientName = "Jin"
    static let placeholderClientID = "jin"
}
