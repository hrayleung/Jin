import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func eventObject(from jsonLine: String) throws -> [String: JSONValue]? {
        guard let data = jsonLine.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(JSONValue.self, from: data).objectValue
    }

    static func eventType(from object: [String: JSONValue]) -> String {
        object.string(at: ["type"])?.lowercased()
            ?? object.string(at: ["event", "type"])?.lowercased()
            ?? object.string(at: ["event_type"])?.lowercased()
            ?? ""
    }

    static func providerError(from object: [String: JSONValue]) -> LLMError {
        LLMError.providerError(
            code: "claude_managed_agents_error",
            message: providerErrorMessage(from: object)
        )
    }

    static func providerErrorMessage(from object: [String: JSONValue]) -> String {
        object.string(at: ["error", "message"])
            ?? object.string(at: ["message"])
            ?? "Claude Managed Agents returned an error event."
    }
}
