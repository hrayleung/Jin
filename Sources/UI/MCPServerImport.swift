import Foundation

struct MCPImportedServer: Sendable, Equatable {
    let id: String
    let name: String
    let transport: MCPTransportConfig
}

enum MCPServerImportError: Error, LocalizedError {
    case unsupportedFormat
    case multipleServers([String])
    case missingHTTPURL
    case invalidHTTPURL(String)
    case missingCommand
    case invalidArgs(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported JSON format."
        case .multipleServers(let ids):
            return "Multiple MCP servers found (\(ids.joined(separator: ", "))). Add a top-level \"id\" to select one."
        case .missingHTTPURL:
            return "Missing \"url\" for HTTP MCP server."
        case .invalidHTTPURL(let value):
            return "Invalid HTTP URL: \(value)"
        case .missingCommand:
            return "Missing \"command\" for MCP server."
        case .invalidArgs(let message):
            return "Invalid args: \(message)"
        }
    }
}

enum MCPServerImportParser {
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
            url: file.url,
            headers: file.headers,
            bearerToken: file.bearerToken,
            streaming: file.streaming
        )
        return try resolveSingle(id: serverID, name: serverName, server: server)
    }

    private static func resolveSingle(id: String, name: String, server: ImportServer) throws -> MCPImportedServer {
        if server.isHTTPLike {
            guard let rawURL = server.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                throw MCPServerImportError.missingHTTPURL
            }
            guard let endpoint = URL(string: rawURL), endpoint.scheme != nil else {
                throw MCPServerImportError.invalidHTTPURL(rawURL)
            }

            let headers = server.headersList()
            let authentication = server.authentication(using: headers)

            return MCPImportedServer(
                id: id,
                name: name,
                transport: .http(
                    MCPHTTPTransportConfig(
                        endpoint: endpoint,
                        streaming: server.streaming ?? true,
                        authentication: authentication,
                        additionalHeaders: headers
                    )
                )
            )
        }

        guard let command = server.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            throw MCPServerImportError.missingCommand
        }

        return MCPImportedServer(
            id: id,
            name: name,
            transport: .stdio(
                MCPStdioTransportConfig(
                    command: command,
                    args: try server.argsTokenized(),
                    env: server.envStringDict()
                )
            )
        )
    }
}

private struct ImportFile: Decodable {
    let id: String?
    let name: String?
    let mcpServers: [String: ImportServer]?

    let command: String?
    let args: ImportArgs?
    let env: [String: ImportScalar]?

    let type: String?
    let url: String?
    let headers: [String: ImportScalar]?
    let bearerToken: String?
    let streaming: Bool?
}

private struct ImportServer: Decodable {
    let name: String?
    let command: String?
    let args: ImportArgs?
    let env: [String: ImportScalar]?

    let type: String?
    let url: String?
    let headers: [String: ImportScalar]?
    let bearerToken: String?
    let streaming: Bool?

    var isHTTPLike: Bool {
        let normalizedType = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedType == "http" { return true }
        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    var trimmedBearerToken: String? {
        let value = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    func argsTokenized() throws -> [String] {
        try args?.tokens() ?? []
    }

    func envStringDict() -> [String: String] {
        guard let env else { return [:] }
        return env.compactMapValues { $0.stringValue }
    }

    func headersList() -> [MCPHeader] {
        guard let headers else { return [] }
        return headers
            .compactMapValues { $0.stringValue }
            .map { key, value in
                MCPHeader(name: key, value: value, isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(key))
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func authentication(using headers: [MCPHeader]) -> MCPHTTPAuthentication {
        if let token = trimmedBearerToken {
            return .bearerToken(token)
        }

        guard let authHeader = headers.first(where: {
            $0.name.caseInsensitiveCompare("Authorization") == .orderedSame
        }) else {
            return .none
        }

        let authValue = authHeader.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if authValue.lowercased().hasPrefix("bearer ") {
            let token = String(authValue.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                return .bearerToken(token)
            }
        }

        return .header(authHeader)
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

private enum ImportScalar: Decodable {
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

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid scalar value")
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
