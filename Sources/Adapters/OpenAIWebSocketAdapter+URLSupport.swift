import Foundation

extension OpenAIWebSocketAdapter {
    func resolvedWebSocketResponsesURL() throws -> URL {
        let fallback = ProviderType.openaiWebSocket.defaultBaseURL ?? "wss://api.openai.com/v1"
        let raw = (providerConfig.baseURL ?? fallback).trimmedNonEmpty ?? fallback
        let base = try validatedURL(raw)
        let normalized = normalizedOpenAIBaseURL(base)
        let wsBase = try coerceToWebSocketScheme(normalized)

        if wsBase.lastPathComponent == "responses" {
            return wsBase
        }
        return wsBase.appendingPathComponent("responses")
    }

    func normalizedOpenAIBaseURL(_ url: URL) -> URL {
        if url.lastPathComponent == "responses" {
            return url.deletingLastPathComponent()
        }
        return url
    }

    func coerceToWebSocketScheme(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LLMError.invalidRequest(message: "Invalid URL: \(url.absoluteString)")
        }

        let scheme = (components.scheme ?? "").lowercased()
        switch scheme {
        case "ws", "wss":
            break
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            throw LLMError.invalidRequest(message: "Invalid WebSocket URL scheme: \(components.scheme ?? "")")
        }

        guard let coerced = components.url else {
            throw LLMError.invalidRequest(message: "Invalid URL: \(url.absoluteString)")
        }
        return coerced
    }

    func resolvedHTTPBaseURLString() -> String {
        let fallback = ProviderType.openai.defaultBaseURL ?? "https://api.openai.com/v1"
        let raw = (providerConfig.baseURL ?? fallback).trimmedNonEmpty ?? fallback
        guard let url = try? validatedURL(raw) else {
            return fallback
        }

        let normalized = normalizedOpenAIBaseURL(url)
        guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            return fallback
        }

        let scheme = (components.scheme ?? "").lowercased()
        switch scheme {
        case "http", "https":
            break
        case "ws":
            components.scheme = "http"
        case "wss":
            components.scheme = "https"
        default:
            components.scheme = "https"
        }

        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url?.absoluteString ?? fallback
    }
}
