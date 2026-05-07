import Foundation

enum MCPServerTransportDraftSupport {
    struct Draft: Equatable {
        var transportKind: MCPTransportKind
        var command: String
        var argsText: String
        var envPairs: [EnvironmentVariablePair]
        var endpoint: String
        var httpAuthentication: MCPHTTPAuthentication
        var headerPairs: [EnvironmentVariablePair]
        var httpStreaming: Bool
    }

    struct BuildRequest {
        var transportKind: MCPTransportKind
        var command: String
        var argsText: String
        var envPairs: [EnvironmentVariablePair]
        var endpoint: String
        var httpAuthentication: MCPHTTPAuthentication?
        var headerPairs: [EnvironmentVariablePair]
        var httpStreaming: Bool
    }

    enum BuildError: Error, Equatable, LocalizedError {
        case invalidArguments(String)
        case invalidEndpointURL
        case invalidAuthentication

        var errorDescription: String? {
            switch self {
            case .invalidArguments(let message):
                return message
            case .invalidEndpointURL:
                return "Invalid endpoint URL."
            case .invalidAuthentication:
                return "Invalid authentication."
            }
        }
    }

    static func draft(from transport: MCPTransportConfig) -> Draft {
        switch transport {
        case .stdio(let stdio):
            return stdioDraft(from: stdio)
        case .http(let http):
            return httpDraft(from: http)
        }
    }

    static func buildTransport(from request: BuildRequest) throws -> MCPTransportConfig {
        switch request.transportKind {
        case .stdio:
            return try buildStdioTransport(from: request)
        case .http:
            return try buildHTTPTransport(from: request)
        }
    }

    private static func stdioDraft(from stdio: MCPStdioTransportConfig) -> Draft {
        Draft(
            transportKind: .stdio,
            command: stdio.command,
            argsText: CommandLineTokenizer.render(stdio.args),
            envPairs: environmentPairs(from: stdio.env),
            endpoint: "",
            httpAuthentication: .none,
            headerPairs: [],
            httpStreaming: true
        )
    }

    private static func httpDraft(from http: MCPHTTPTransportConfig) -> Draft {
        Draft(
            transportKind: .http,
            command: "",
            argsText: "",
            envPairs: [],
            endpoint: http.endpoint.absoluteString,
            httpAuthentication: http.authentication,
            headerPairs: headerPairs(from: http.additionalHeaders),
            httpStreaming: http.streaming
        )
    }

    private static func buildStdioTransport(from request: BuildRequest) throws -> MCPTransportConfig {
        let parsedArgs: [String]
        do {
            parsedArgs = try CommandLineTokenizer.tokenize(request.argsText)
        } catch {
            throw BuildError.invalidArguments(error.localizedDescription)
        }

        return .stdio(
            MCPStdioTransportConfig(
                command: request.command.trimmingCharacters(in: .whitespacesAndNewlines),
                args: parsedArgs,
                env: MCPServerFormSupport.environmentDictionary(from: request.envPairs)
            )
        )
    }

    private static func buildHTTPTransport(from request: BuildRequest) throws -> MCPTransportConfig {
        guard let endpoint = MCPServerFormSupport.parsedEndpoint(request.endpoint) else {
            throw BuildError.invalidEndpointURL
        }
        guard let authentication = request.httpAuthentication else {
            throw BuildError.invalidAuthentication
        }

        return .http(
            MCPHTTPTransportConfig(
                endpoint: endpoint,
                streaming: request.httpStreaming,
                authentication: authentication,
                additionalHeaders: MCPServerFormSupport.headers(from: request.headerPairs)
            )
        )
    }

    private static func environmentPairs(from env: [String: String]) -> [EnvironmentVariablePair] {
        env.keys.sorted().map { key in
            EnvironmentVariablePair(key: key, value: env[key] ?? "")
        }
    }

    private static func headerPairs(from headers: [MCPHeader]) -> [EnvironmentVariablePair] {
        headers.map { header in
            EnvironmentVariablePair(key: header.name, value: header.value)
        }
    }
}
