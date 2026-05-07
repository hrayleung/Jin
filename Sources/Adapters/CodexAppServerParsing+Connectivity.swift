import Foundation
import Network

extension CodexAppServerAdapter {
    nonisolated static func remapCodexConnectivityError(_ error: Error, endpoint: URL) -> Error {
        guard let guidance = codexConnectivityGuidanceMessage(for: error, endpoint: endpoint) else {
            return error
        }
        return LLMError.providerError(code: "codex_server_unavailable", message: guidance)
    }

    nonisolated static func codexConnectivityGuidanceMessage(
        for error: Error,
        endpoint: URL
    ) -> String? {
        guard isLikelyCodexServerUnavailable(error) else { return nil }
        let endpointString = endpoint.absoluteString
        return """
        Cannot connect to Codex App Server at \(endpointString).

        If you're using a local server, start it first:
        - Jin -> Settings -> Providers -> Codex App Server (Beta) -> Start Server
        - Terminal: codex app-server --listen \(endpointString)

        If you're using a remote endpoint, verify the URL/network and retry.
        """
    }

    private nonisolated static func isLikelyCodexServerUnavailable(_ error: Error) -> Bool {
        if case LLMError.invalidRequest(let message) = error,
           message.localizedCaseInsensitiveContains("not connected") {
            return true
        }

        guard case LLMError.networkError(let underlying) = error else {
            return false
        }

        if isLikelyConnectionPOSIXError(underlying) {
            return true
        }

        let description = underlying.localizedDescription.lowercased()
        let connectivityHints = [
            "connection refused",
            "failed to connect",
            "timed out",
            "network is unreachable",
            "host is down",
            "socket is not connected",
            "websocket connection was cancelled",
            "connection reset",
            "connection aborted",
            "broken pipe",
        ]
        return connectivityHints.contains { description.contains($0) }
    }

    private nonisolated static func isLikelyConnectionPOSIXError(_ error: Error) -> Bool {
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                return isLikelyConnectionPOSIXCode(Int32(code.rawValue))
            case .dns:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return isLikelyConnectionPOSIXCode(Int32(nsError.code))
        }
        return false
    }

    private nonisolated static func isLikelyConnectionPOSIXCode(_ code: Int32) -> Bool {
        code == ECONNREFUSED
            || code == ETIMEDOUT
            || code == EHOSTUNREACH
            || code == ENETUNREACH
            || code == EHOSTDOWN
            || code == ECONNRESET
            || code == ECONNABORTED
            || code == EPIPE
    }
}
