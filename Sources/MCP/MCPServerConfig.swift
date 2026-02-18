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

enum MCPHTTPAuthentication: Codable, Equatable, Sendable {
    case none
    case bearerToken(String)
    case header(MCPHeader)

    private enum CodingKeys: String, CodingKey {
        case type
        case token
        case header
    }

    private enum Kind: String, Codable {
        case none
        case bearerToken
        case header
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .none

        switch kind {
        case .none:
            self = .none
        case .bearerToken:
            self = .bearerToken(try container.decode(String.self, forKey: .token))
        case .header:
            self = .header(try container.decode(MCPHeader.self, forKey: .header))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .type)
        case .bearerToken(let token):
            try container.encode(Kind.bearerToken, forKey: .type)
            try container.encode(token, forKey: .token)
        case .header(let header):
            try container.encode(Kind.header, forKey: .type)
            try container.encode(header, forKey: .header)
        }
    }

    var resolvedHeader: MCPHeader? {
        switch self {
        case .none:
            return nil
        case .bearerToken(let token):
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedToken.isEmpty else { return nil }
            return MCPHeader(name: "Authorization", value: "Bearer \(trimmedToken)", isSensitive: true)
        case .header(let header):
            let trimmedName = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            return MCPHeader(
                name: trimmedName,
                value: header.value,
                isSensitive: header.isSensitive || MCPHTTPTransportConfig.isSensitiveHeaderName(trimmedName)
            )
        }
    }

    /// Returns a cleaned-up version: trims whitespace and collapses empty values to `.none`.
    var normalized: MCPHTTPAuthentication {
        switch self {
        case .none:
            return .none
        case .bearerToken(let token):
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .none : .bearerToken(trimmed)
        case .header(let header):
            let trimmedName = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return .none }
            return .header(
                MCPHeader(
                    name: trimmedName,
                    value: header.value,
                    isSensitive: header.isSensitive || MCPHTTPTransportConfig.isSensitiveHeaderName(trimmedName)
                )
            )
        }
    }

    // MARK: - Form helpers

    /// Picker-friendly representation for SwiftUI forms.
    enum FormKind: String, CaseIterable {
        case none
        case bearerToken
        case customHeader
    }

    /// Returns a validation error message when the form fields are incomplete, or nil when valid.
    static func formValidationError(
        kind: FormKind,
        bearerToken: String,
        headerName: String,
        headerValue: String
    ) -> String? {
        switch kind {
        case .none:
            return nil
        case .bearerToken:
            return bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Bearer token is required." : nil
        case .customHeader:
            if headerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Header name is required."
            }
            if headerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Header value is required."
            }
            return nil
        }
    }

    /// Builds an `MCPHTTPAuthentication` from form fields, returning nil when validation fails.
    static func fromFormFields(
        kind: FormKind,
        bearerToken: String,
        headerName: String,
        headerValue: String
    ) -> MCPHTTPAuthentication? {
        guard formValidationError(kind: kind, bearerToken: bearerToken, headerName: headerName, headerValue: headerValue) == nil else {
            return nil
        }
        switch kind {
        case .none:
            return MCPHTTPAuthentication.none
        case .bearerToken:
            return .bearerToken(bearerToken.trimmingCharacters(in: .whitespacesAndNewlines))
        case .customHeader:
            let name = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return .header(
                MCPHeader(
                    name: name,
                    value: headerValue,
                    isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(name)
                )
            )
        }
    }

    /// Decomposes this authentication value into form-field components.
    struct FormFields {
        var kind: FormKind
        var bearerToken: String
        var headerName: String
        var headerValue: String
    }

    var formFields: FormFields {
        switch self {
        case .none:
            return FormFields(kind: .none, bearerToken: "", headerName: "Authorization", headerValue: "")
        case .bearerToken(let token):
            return FormFields(kind: .bearerToken, bearerToken: token, headerName: "Authorization", headerValue: "")
        case .header(let header):
            return FormFields(kind: .customHeader, bearerToken: "", headerName: header.name, headerValue: header.value)
        }
    }
}

struct MCPHTTPTransportConfig: Codable, Equatable, Sendable {
    var endpoint: URL
    var streaming: Bool
    var authentication: MCPHTTPAuthentication
    var additionalHeaders: [MCPHeader]

    init(
        endpoint: URL,
        streaming: Bool = true,
        authentication: MCPHTTPAuthentication = .none,
        additionalHeaders: [MCPHeader] = []
    ) {
        self.endpoint = endpoint
        self.streaming = streaming
        let normalized = Self.normalize(authentication: authentication, additionalHeaders: additionalHeaders)
        self.authentication = normalized.authentication
        self.additionalHeaders = normalized.additionalHeaders
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case streaming
        case authentication
        case additionalHeaders

        // Legacy keys: used by already-persisted data.
        case headers
        case bearerToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let endpoint = try container.decode(URL.self, forKey: .endpoint)
        let streaming = try container.decodeIfPresent(Bool.self, forKey: .streaming) ?? true

        let decodedAuthentication = try container.decodeIfPresent(MCPHTTPAuthentication.self, forKey: .authentication)
        let decodedHeaders = try container.decodeIfPresent([MCPHeader].self, forKey: .additionalHeaders)
        let legacyHeaders = try container.decodeIfPresent([MCPHeader].self, forKey: .headers)

        var authentication = decodedAuthentication ?? .none
        if case .none = authentication,
           let bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken),
           !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            authentication = .bearerToken(bearerToken)
        }

        self.init(
            endpoint: endpoint,
            streaming: streaming,
            authentication: authentication,
            additionalHeaders: decodedHeaders ?? legacyHeaders ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(streaming, forKey: .streaming)
        try container.encode(authentication, forKey: .authentication)
        try container.encode(additionalHeaders, forKey: .additionalHeaders)
    }

    func resolvedHeaders() -> [String: String] {
        var values: [String: String] = [:]

        for header in additionalHeaders {
            let key = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            values[key] = header.value
        }

        if let authHeader = authentication.resolvedHeader {
            values[authHeader.name] = authHeader.value
        }

        return values
    }

    private static func normalize(
        authentication: MCPHTTPAuthentication,
        additionalHeaders: [MCPHeader]
    ) -> (authentication: MCPHTTPAuthentication, additionalHeaders: [MCPHeader]) {
        var normalizedHeaders = additionalHeaders.compactMap { header -> MCPHeader? in
            let key = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return MCPHeader(
                name: key,
                value: header.value,
                isSensitive: header.isSensitive || isSensitiveHeaderName(key)
            )
        }

        var normalizedAuthentication = authentication.normalized

        if case .none = normalizedAuthentication,
           let authHeader = normalizedHeaders.first(where: { isAuthorizationHeader($0.name) }) {
            normalizedAuthentication = .header(authHeader)
        }

        if let authHeaderName = normalizedAuthentication.resolvedHeader?.name {
            normalizedHeaders.removeAll { $0.name.caseInsensitiveCompare(authHeaderName) == .orderedSame }
        }

        return (normalizedAuthentication, normalizedHeaders)
    }

    private static func isAuthorizationHeader(_ name: String) -> Bool {
        name.caseInsensitiveCompare("Authorization") == .orderedSame
    }

    static func isSensitiveHeaderName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["authorization", "proxy-authorization", "x-api-key", "api-key"].contains(normalized)
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
