import Foundation

/// Tool definition (from MCP or built-in)
struct ToolDefinition: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let parameters: ParameterSchema
    let source: ToolSource

    init(id: String, name: String, description: String, parameters: ParameterSchema, source: ToolSource) {
        self.id = id
        self.name = name
        self.description = description
        self.parameters = parameters
        self.source = source
    }
}

/// Parameter schema (JSON Schema)
struct ParameterSchema: Codable, Sendable {
    let type: String // "object"
    let properties: [String: PropertySchema]
    let required: [String]

    init(type: String = "object", properties: [String: PropertySchema], required: [String] = []) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Property schema for parameters
struct PropertySchema: Codable, Sendable {
    let type: String // "string", "number", "boolean", "array", "object"
    let description: String?
    let items: Box<PropertySchema>? // For arrays
    let properties: [String: Box<PropertySchema>]? // For nested objects
    let enumValues: [String]? // For enums

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case properties
        case enumValues = "enum"
    }

    init(
        type: String,
        description: String? = nil,
        items: PropertySchema? = nil,
        properties: [String: PropertySchema]? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.items = items.map { Box($0) }
        self.properties = properties?.mapValues { Box($0) }
        self.enumValues = enumValues
    }

    /// Convert to a JSON-compatible dictionary for use with JSONSerialization.
    /// This avoids a Swift compiler crash (signal 11) when iterating over PropertySchema
    /// fields in generic/closure contexts due to the recursive Box<PropertySchema> fields.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let description = description {
            dict["description"] = description
        }
        if let enumValues = enumValues {
            dict["enum"] = enumValues
        }
        if let items = items {
            dict["items"] = items.value.toDictionary()
        }
        if let properties = properties {
            var propsDict: [String: Any] = [:]
            for (key, boxed) in properties {
                propsDict[key] = boxed.value.toDictionary()
            }
            dict["properties"] = propsDict
        }
        return dict
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        items = try container.decodeIfPresent(Box<PropertySchema>.self, forKey: .items)
        properties = try container.decodeIfPresent([String: Box<PropertySchema>].self, forKey: .properties)
        enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
    }
}

/// Box type for indirect storage (class to allow recursive value types)
final class Box<T: Codable & Sendable>: Codable, Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(T.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Source of the tool
enum ToolSource: Codable {
    case mcp(serverID: String)
    case builtin

    enum CodingKeys: String, CodingKey {
        case type
        case serverID
    }

    enum SourceType: String, Codable {
        case mcp
        case builtin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)

        switch type {
        case .mcp:
            let serverID = try container.decode(String.self, forKey: .serverID)
            self = .mcp(serverID: serverID)
        case .builtin:
            self = .builtin
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .mcp(let serverID):
            try container.encode(SourceType.mcp, forKey: .type)
            try container.encode(serverID, forKey: .serverID)
        case .builtin:
            try container.encode(SourceType.builtin, forKey: .type)
        }
    }
}
