import Foundation

enum ClaudeManagedAgentCatalogSupport {
    static func collectionObject(from data: Data) throws -> [String: JSONValue] {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = decoded.objectValue else {
            throw LLMError.decodingError(message: "Managed Agents list response was not an object.")
        }
        return object
    }

    static func agentDescriptors(from object: [String: JSONValue]) -> [ClaudeManagedAgentDescriptor] {
        collectionItems(from: object).compactMap(agentDescriptor(from:))
    }

    static func environmentDescriptors(from object: [String: JSONValue]) -> [ClaudeManagedEnvironmentDescriptor] {
        collectionItems(from: object).compactMap(environmentDescriptor(from:))
    }

    static func collectionItems(from object: [String: JSONValue]) -> [[String: JSONValue]] {
        if let data = object.array(at: ["data"])?.compactMap(\.objectValue), !data.isEmpty {
            return data
        }
        if let items = object.array(at: ["items"])?.compactMap(\.objectValue), !items.isEmpty {
            return items
        }
        if let agents = object.array(at: ["agents"])?.compactMap(\.objectValue), !agents.isEmpty {
            return agents
        }
        if let environments = object.array(at: ["environments"])?.compactMap(\.objectValue), !environments.isEmpty {
            return environments
        }
        return []
    }

    private static func agentDescriptor(from item: [String: JSONValue]) -> ClaudeManagedAgentDescriptor? {
        guard let id = normalizedTrimmedString(
            item.string(at: ["id"])
                ?? item.string(at: ["agent", "id"])
        ) else {
            return nil
        }

        let name = normalizedTrimmedString(
            item.string(at: ["name"])
                ?? item.string(at: ["display_name"])
                ?? item.string(at: ["agent", "name"])
                ?? item.string(at: ["agent", "display_name"])
        ) ?? id

        let modelID = normalizedTrimmedString(
            item.string(at: ["model", "id"])
                ?? item.string(at: ["agent", "model", "id"])
                ?? item.string(at: ["model_id"])
                ?? item.string(at: ["agent", "model_id"])
                ?? item.string(at: ["agent", "model"])
                ?? item.string(at: ["model"])
        )

        let modelDisplayName = normalizedTrimmedString(
            item.string(at: ["model", "display_name"])
                ?? item.string(at: ["model", "name"])
                ?? item.string(at: ["agent", "model", "display_name"])
                ?? item.string(at: ["agent", "model", "name"])
        )

        return ClaudeManagedAgentDescriptor(
            id: id,
            name: name,
            modelID: modelID,
            modelDisplayName: modelDisplayName
        )
    }

    private static func environmentDescriptor(from item: [String: JSONValue]) -> ClaudeManagedEnvironmentDescriptor? {
        guard let id = normalizedTrimmedString(
            item.string(at: ["id"])
                ?? item.string(at: ["environment", "id"])
        ) else {
            return nil
        }

        let name = normalizedTrimmedString(
            item.string(at: ["name"])
                ?? item.string(at: ["display_name"])
                ?? item.string(at: ["environment", "name"])
                ?? item.string(at: ["environment", "display_name"])
        ) ?? id

        return ClaudeManagedEnvironmentDescriptor(id: id, name: name)
    }
}
