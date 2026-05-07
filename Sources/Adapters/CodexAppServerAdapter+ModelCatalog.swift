import Foundation

extension CodexAppServerAdapter {
    func validateAPIKey(_ key: String) async throws -> Bool {
        do {
            return try await withInitializedClient { client in
                if let trimmed = Self.trimmedValue(key) {
                    try await authenticateWithAPIKey(trimmed, client: client)
                    return true
                }

                let status = try await readAccountStatus(using: client, refreshToken: false)
                return status.isAuthenticated
            }
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        try await withInitializedClient { client in
            try await authenticateSession(client)

            var allModels: [ModelInfo] = []
            var cursor: String?

            repeat {
                var params: [String: Any] = [:]
                if let cursor, !cursor.isEmpty {
                    params["cursor"] = cursor
                }

                let result = try await requestWithServerRequestHandling(
                    client: client,
                    method: "model/list",
                    params: params
                )
                guard let object = result.objectValue else {
                    throw LLMError.decodingError(message: "Codex model/list returned unexpected payload.")
                }

                if let data = object.array(at: ["data"]) {
                    for item in data {
                        guard let modelObject = item.objectValue else { continue }
                        guard let modelInfo = Self.makeModelInfo(from: modelObject) else { continue }
                        allModels.append(modelInfo)
                    }
                }

                if let nextCursor = Self.trimmedValue(object.string(at: ["nextCursor"])) {
                    cursor = nextCursor
                } else {
                    cursor = nil
                }
            } while cursor != nil

            if allModels.isEmpty {
                return [
                    ModelInfo(
                        id: "gpt-5.1-codex",
                        name: "GPT-5.1 Codex",
                        capabilities: [.streaming, .reasoning],
                        contextWindow: Self.fallbackContextWindow,
                        reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                    )
                ]
            }

            return allModels.sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
