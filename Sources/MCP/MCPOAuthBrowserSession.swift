import Foundation
#if os(macOS)
import AppKit
#endif

/// Opens the system browser and waits for the OAuth loopback redirect.
final class MCPOAuthBrowserSession: Sendable {
    func start(authorizationURL: URL) async throws -> URL {
        guard let redirectURI = MCPOAuthLoopbackListener.redirectURI(fromAuthorizationURL: authorizationURL) else {
            throw MCPOAuthError.authorizationFailed("The sign-in URL is missing a redirect URI.")
        }

        let server = MCPOAuthLoopbackServer()
        try await server.start(redirectURI: redirectURI)
        defer { server.stop() }

        try await openBrowser(authorizationURL)

        let callback = try await server.accept(timeoutSeconds: 300)
        if let message = MCPOAuthLoopbackListener.errorMessage(fromCallback: callback) {
            let lowered = message.lowercased()
            if lowered == "access_denied" || lowered.contains("denied") {
                throw MCPOAuthError.cancelled
            }
            throw MCPOAuthError.authorizationFailed(message)
        }
        return callback
    }

    @MainActor
    private func openBrowser(_ url: URL) throws {
        #if os(macOS)
        guard NSWorkspace.shared.open(url) else {
            throw MCPOAuthError.browserUnavailable
        }
        #else
        throw MCPOAuthError.browserUnavailable
        #endif
    }
}
