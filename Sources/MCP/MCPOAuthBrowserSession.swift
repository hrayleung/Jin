import AuthenticationServices
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class MCPOAuthBrowserSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: MCPOAuthConstants.callbackScheme
            ) { callbackURL, error in
                self.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: MCPOAuthError.cancelled)
                        return
                    }
                    continuation.resume(throwing: MCPOAuthError.authorizationFailed(error.localizedDescription))
                    return
                }
                continuation.resume(throwing: MCPOAuthError.cancelled)
            }

            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            self.session = authSession

            if !authSession.start() {
                self.session = nil
                continuation.resume(throwing: MCPOAuthError.browserUnavailable)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
        #else
        ASPresentationAnchor()
        #endif
    }
}
