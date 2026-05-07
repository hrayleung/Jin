import Foundation

extension CodexAppServerFormSupport {
    static var defaultListenURL: String {
        ProviderType.codexAppServer.defaultBaseURL ?? "ws://127.0.0.1:4500"
    }

    static func listenURL(baseURL: String?) -> String {
        baseURL?.trimmedNonEmpty ?? defaultListenURL
    }

    static func listenURLValidationError(_ listenURL: String) -> String? {
        guard let parsed = URL(string: listenURL),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            return "Base URL must be a valid ws:// or wss:// listen address to launch app-server."
        }

        guard let host = parsed.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost" || host == "::1" else {
            return "In-app app-server launch only supports localhost listen addresses."
        }

        return nil
    }
}
