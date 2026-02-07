import Foundation

enum MCPLifecyclePolicy: String, Codable, CaseIterable, Sendable {
    case persistent
    case ephemeral

    var isPersistent: Bool {
        self == .persistent
    }
}

enum MCPTransportKind: String, Codable, CaseIterable, Sendable {
    case stdio
    case http
}

struct MCPHeader: Codable, Equatable, Sendable {
    var name: String
    var value: String
    var isSensitive: Bool

    init(name: String, value: String, isSensitive: Bool = false) {
        self.name = name
        self.value = value
        self.isSensitive = isSensitive
    }
}

struct MCPStdioTransportConfig: Codable, Equatable, Sendable {
    var command: String
    var args: [String]
    var env: [String: String]

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }
}

struct MCPHTTPTransportConfig: Codable, Equatable, Sendable {
    var endpoint: URL
    var streaming: Bool
    var headers: [MCPHeader]
    var bearerToken: String?

    init(
        endpoint: URL,
        streaming: Bool = true,
        headers: [MCPHeader] = [],
        bearerToken: String? = nil
    ) {
        self.endpoint = endpoint
        self.streaming = streaming
        self.headers = headers
        self.bearerToken = bearerToken
    }

    func resolvedHeaders() -> [String: String] {
        var values: [String: String] = [:]

        for header in headers {
            let key = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            values[key] = header.value
        }

        if let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            values["Authorization"] = "Bearer \(token)"
        }

        return values
    }
}

enum MCPTransportConfig: Codable, Equatable, Sendable {
    case stdio(MCPStdioTransportConfig)
    case http(MCPHTTPTransportConfig)

    var kind: MCPTransportKind {
        switch self {
        case .stdio:
            return .stdio
        case .http:
            return .http
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case stdio
        case http
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(MCPTransportKind.self, forKey: .kind)

        switch kind {
        case .stdio:
            let config = try container.decode(MCPStdioTransportConfig.self, forKey: .stdio)
            self = .stdio(config)
        case .http:
            let config = try container.decode(MCPHTTPTransportConfig.self, forKey: .http)
            self = .http(config)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .stdio(let config):
            try container.encode(config, forKey: .stdio)
        case .http(let config):
            try container.encode(config, forKey: .http)
        }
    }
}

struct MCPServerConfig: Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var isEnabled: Bool
    var runToolsAutomatically: Bool
    var lifecycle: MCPLifecyclePolicy
    var transport: MCPTransportConfig
    var disabledTools: Set<String> = []

    var isLongRunning: Bool {
        lifecycle.isPersistent
    }
}
