import Foundation

struct MCPImportedServer: Sendable, Equatable {
    let id: String
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
}

enum MCPServerImportError: Error, LocalizedError {
    case unsupportedFormat
    case multipleServers([String])
    case missingHTTPURL
    case missingCommand
    case invalidArgs(String)
    case invalidEnvValue(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported JSON format."
        case .multipleServers(let ids):
            return "Multiple MCP servers found (\(ids.joined(separator: ", "))). Add a top-level \"id\" to select one."
        case .missingHTTPURL:
            return "Missing \"url\" for HTTP MCP server."
        case .missingCommand:
            return "Missing \"command\" for MCP server."
        case .invalidArgs(let message):
            return "Invalid args: \(message)"
        case .invalidEnvValue(let key):
            return "Invalid env value for key: \(key)"
        }
    }
}

struct MCPServerImportParser {
    static func parse(json: String) throws -> MCPImportedServer {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let file = try decoder.decode(ImportFile.self, from: data)
        return try resolve(file)
    }

    private static func resolve(_ file: ImportFile) throws -> MCPImportedServer {
        if let mcpServers = file.mcpServers {
            let selectedID: String
            if let explicit = file.id, mcpServers.keys.contains(explicit) {
                selectedID = explicit
            } else if mcpServers.count == 1, let only = mcpServers.keys.first {
                selectedID = only
            } else {
                throw MCPServerImportError.multipleServers(mcpServers.keys.sorted())
            }

            guard let server = mcpServers[selectedID] else {
                throw MCPServerImportError.unsupportedFormat
            }

            return try resolveSingle(
                id: selectedID,
                name: file.name ?? server.name ?? selectedID,
                server: server
            )
        }

        let serverID = (file.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString
            : (file.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverName = (file.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? serverID
            : (file.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let server = ImportServer(
            name: nil,
            command: file.command,
            args: file.args,
            env: file.env,
            type: file.type,
            url: file.url
        )
        return try resolveSingle(id: serverID, name: serverName, server: server)
    }

    private static func resolveSingle(id: String, name: String, server: ImportServer) throws -> MCPImportedServer {
        if let type = server.type?.trimmingCharacters(in: .whitespacesAndNewlines),
           type.lowercased() == "http" {
            guard let url = server.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
                throw MCPServerImportError.missingHTTPURL
            }

            return MCPImportedServer(
                id: id,
                name: name,
                command: "npx",
                args: ["-y", "mcp-remote", url],
                env: server.envStringDict()
            )
        }

        guard let command = server.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            throw MCPServerImportError.missingCommand
        }

        return MCPImportedServer(
            id: id,
            name: name,
            command: command,
            args: try server.argsTokenized(),
            env: server.envStringDict()
        )
    }
}

private struct ImportFile: Decodable {
    let id: String?
    let name: String?
    let mcpServers: [String: ImportServer]?

    let command: String?
    let args: ImportArgs?
    let env: [String: ImportEnvValue]?

    let type: String?
    let url: String?
}

private struct ImportServer: Decodable {
    let name: String?
    let command: String?
    let args: ImportArgs?
    let env: [String: ImportEnvValue]?

    let type: String?
    let url: String?

    func argsTokenized() throws -> [String] {
        try args?.tokens() ?? []
    }

    func envStringDict() -> [String: String] {
        guard let env else { return [:] }
        return env.compactMapValues { $0.stringValue }
    }
}

private enum ImportArgs: Decodable {
    case array([String])
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid args")
    }

    func tokens() throws -> [String] {
        switch self {
        case .array(let value):
            return value
        case .string(let value):
            do {
                return try CommandLineTokenizer.tokenize(value)
            } catch {
                throw MCPServerImportError.invalidArgs(error.localizedDescription)
            }
        }
    }
}

private enum ImportEnvValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }

        if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
            return
        }

        if let double = try? container.decode(Double.self) {
            self = .number(double)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid env value")
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return nil
        }
    }
}

