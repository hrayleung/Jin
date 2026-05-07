import Foundation

extension OpenAIWebSocketAdapter {
    nonisolated static func responseCreateEvent(from responsePayload: [String: Any]) -> [String: Any] {
        var event = responsePayload
        event["type"] = "response.create"
        return event
    }

    nonisolated static func decodeErrorEventPayload(_ jsonData: Data, fallbackMessage: String) -> LLMError {
        let payload = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
        let error = payload?["error"] as? [String: Any]
        let code = (error?["code"] as? String)
            ?? (error?["type"] as? String)
            ?? "error"
        let message = (error?["message"] as? String)
            ?? (payload?["message"] as? String)
            ?? fallbackMessage
        return .providerError(code: code, message: message)
    }
}
