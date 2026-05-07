import Foundation

extension CodexAppServerAdapter {
    func translateTools(_ tools: [ToolDefinition]) -> Any {
        _ = tools
        return [[String: Any]]()
    }

    func makeThreadStartParams(modelID: String, controls: GenerationControls) -> [String: Any] {
        CodexAppServerRequestBuilder.threadStartParams(modelID: modelID, controls: controls)
    }

    func makeThreadResumeParams(threadID: String, modelID: String, controls: GenerationControls) -> [String: Any] {
        CodexAppServerRequestBuilder.threadResumeParams(threadID: threadID, modelID: modelID, controls: controls)
    }

    func makeTurnStartParams(
        threadID: String,
        inputItems: [Any],
        controls: GenerationControls,
        modelID: String
    ) -> [String: Any] {
        CodexAppServerRequestBuilder.turnStartParams(
            threadID: threadID,
            inputItems: inputItems,
            modelID: modelID,
            controls: controls
        )
    }

    func resolvedEndpointURL() throws -> URL {
        let fallback = ProviderType.codexAppServer.defaultBaseURL ?? "ws://127.0.0.1:4500"
        guard let raw = Self.trimmedValue(providerConfig.baseURL ?? fallback) else {
            throw LLMError.invalidRequest(message: "Codex App Server base URL is empty.")
        }

        let normalized: String
        if raw.hasPrefix("ws://") || raw.hasPrefix("wss://") {
            normalized = raw
        } else if raw.hasPrefix("http://") {
            normalized = "ws://\(raw.dropFirst("http://".count))"
        } else if raw.hasPrefix("https://") {
            normalized = "wss://\(raw.dropFirst("https://".count))"
        } else {
            normalized = "ws://\(raw)"
        }

        guard let url = URL(string: normalized) else {
            throw LLMError.invalidRequest(message: "Invalid Codex App Server URL: \(raw)")
        }
        return url
    }

    nonisolated static func extractThreadID(from result: JSONValue) -> String? {
        if let threadID = result.objectValue?.string(at: ["thread", "id"]), !threadID.isEmpty {
            return threadID
        }
        if let threadID = result.objectValue?.string(at: ["threadId"]), !threadID.isEmpty {
            return threadID
        }
        return nil
    }

    nonisolated static func shouldFallbackToFreshThread(_ error: Error) -> Bool {
        guard case let LLMError.providerError(code, message) = error else {
            return false
        }

        let lower = message.lowercased()
        return lower.contains("not found")
            || lower.contains("unknown thread")
            || lower.contains("no such thread")
            || (code == "-32602" && lower.contains("missing thread"))
    }
}
