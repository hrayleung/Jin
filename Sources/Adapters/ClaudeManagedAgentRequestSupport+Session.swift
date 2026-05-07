import Foundation

extension ClaudeManagedAgentRequestSupport {
    static func sessionState(from data: Data) throws -> ClaudeManagedAgentSessionState {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try sessionState(from: json)
    }

    static func sessionState(from json: [String: Any]?) throws -> ClaudeManagedAgentSessionState {
        let object = jsonValueObject(from: json)
        let sessionID = normalizedTrimmedString(json?["id"] as? String)
            ?? normalizedTrimmedString((json?["session"] as? [String: Any])?["id"] as? String)
            ?? object.string(at: ["id"])
            ?? object.string(at: ["session", "id"])

        guard let sessionID else {
            throw LLMError.decodingError(
                message: "Claude Managed Agents session response did not include an id."
            )
        }

        return ClaudeManagedAgentSessionState(
            remoteSessionID: sessionID,
            remoteModelID: ClaudeManagedAgentStreamParsingSupport.extractRemoteModelID(from: object)
        )
    }

    private static func jsonValueObject(from json: [String: Any]?) -> [String: JSONValue] {
        guard let json,
              let value = try? JSONValue(any: json),
              let object = value.objectValue else {
            return [:]
        }
        return object
    }
}
