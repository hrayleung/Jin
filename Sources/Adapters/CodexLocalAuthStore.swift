import Foundation

struct CodexLocalAuthStore {
    static let authModeHint = "codex.auth.local_json.v1"

    private static let apiKeyCandidates = [
        "OPENAI_API_KEY",
        "openai_api_key",
        "openaiApiKey",
        "apiKey",
        "api_key"
    ]

    static func loadAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let authURL = authFileURL(environment: environment)
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any] else {
            return nil
        }
        return extractAPIKey(from: object)
    }

    static func authFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let codexHome = environment["CODEX_HOME"]?.trimmedNonEmpty {
            return URL(fileURLWithPath: codexHome, isDirectory: true)
                .appendingPathComponent("auth.json", isDirectory: false)
        }

        let homeDirectory = environment["HOME"]?.trimmedNonEmpty
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    static func extractAPIKey(from payload: [String: Any]) -> String? {
        for key in apiKeyCandidates {
            if let value = payload[key] as? String,
               let trimmed = value.trimmedNonEmpty {
                return trimmed
            }
        }
        return nil
    }
}
