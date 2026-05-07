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

        let serverID = MCPServerFormSupport.normalizedServerID(file.id ?? "")
        let serverName = MCPServerFormSupport.normalizedServerName(file.name, fallback: serverID)

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
            guard let rawURL = server.normalizedURLString else {
                throw MCPServerImportError.missingHTTPURL
            }
            guard let endpoint = MCPServerFormSupport.parsedEndpoint(rawURL) else {
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

        guard let command = server.normalizedCommand else {
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

enum MCPServerImportErrorPresentation {
    static func message(for error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return message(for: decodingError)
        }

        if let importError = error as? MCPServerImportError {
            return importError.localizedDescription
        }

        return error.localizedDescription
    }

    private static func message(for error: DecodingError) -> String {
        func codingPathString(_ path: [CodingKey]) -> String {
            guard !path.isEmpty else { return "(root)" }
            return path.map(\.stringValue).joined(separator: ".")
        }

        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            return "\(context.debugDescription)\nPath: \(codingPathString(context.codingPath))"
        @unknown default:
            return error.localizedDescription
        }
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
        let normalizedType = type?.trimmedLowercased
        if normalizedType == "http" { return true }
        if normalizedURLString != nil {
            return true
        }
        return false
    }

    var normalizedURLString: String? {
        url?.trimmedNonEmpty
    }

    var normalizedCommand: String? {
        command?.trimmedNonEmpty
    }

    var trimmedBearerToken: String? {
        bearerToken?.trimmedNonEmpty
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
                MCPServerFormSupport.header(name: key, value: value)
            }
            .compactMap(\.self)
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

        if let authValue = authHeader.value.trimmedNonEmpty,
           authValue.lowercased().hasPrefix("bearer ") {
            if let token = String(authValue.dropFirst("bearer ".count)).trimmedNonEmpty {
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
