import Foundation

extension OpenAIWebSocketAdapter {
    func openWebSocket() async throws -> URLSessionWebSocketTask {
        if let existing = webSocketTask, existing.state == .running {
            return existing
        }

        let socketURL = try resolvedWebSocketResponsesURL()
        var request = URLRequest(url: socketURL)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        task.resume()

        webSocketTask = task
        return task
    }

    func cancelResponseIfPossible() async {
        guard isResponseInFlight else { return }
        guard let webSocketTask, webSocketTask.state == .running else { return }

        let cancelEvent: [String: Any] = ["type": "response.cancel"]
        guard let data = try? JSONSerialization.data(withJSONObject: cancelEvent),
              let message = String(data: data, encoding: .utf8) else {
            return
        }

        try? await webSocketTask.send(.string(message))
    }

    func resetWebSocketState() {
        isResponseInFlight = false
        previousResponseID = nil
        activeTraceSessionID = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func continuationState(for messages: [Message]) -> (messages: [Message], previousResponseID: String?) {
        guard let previousResponseID else {
            return (messages, nil)
        }

        guard let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }),
              lastAssistantIndex < messages.count - 1 else {
            return (messages, previousResponseID)
        }

        let suffix = Array(messages.suffix(from: messages.index(after: lastAssistantIndex)))
        return (suffix, previousResponseID)
    }
}
