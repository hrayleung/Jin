import Foundation

/// Opaque snapshot of tool-name → server/tool routing produced by
/// `toolDefinitions(for:)`. Each call site holds its own snapshot,
/// so concurrent conversations with different server configs never
/// clobber each other's routes.
struct ToolRouteSnapshot: Sendable {
    fileprivate let routes: [String: MCPHub.ToolRoute]

    func routeInfo(for functionName: String) -> (serverID: String, toolName: String)? {
        guard let route = routes[functionName] else { return nil }
        return (route.server.id, route.toolName)
    }
}

actor MCPHub {
    static let shared = MCPHub()
    static let functionNameSeparator = "__"
    static let functionNameMaxLength = 64
    private static let functionNameShortServerIDLength = 8

    private var clients: [String: MCPClient] = [:]
    private var clientConfigs: [String: MCPServerConfig] = [:]

    func listTools(for server: MCPServerConfig) async throws -> [MCPToolInfo] {
        try await withClient(for: server) { client in
            try await client.listTools()
        }
    }

    func toolDefinitions(for servers: [MCPServerConfig]) async throws -> (definitions: [ToolDefinition], routes: ToolRouteSnapshot) {
        var serverTools: [(server: MCPServerConfig, tools: [MCPToolInfo])] = []

        for server in servers where server.isEnabled {
            let tools = try await withClient(for: server) { client in
                try await client.listTools()
            }
            serverTools.append((server, tools))
        }

        return Self.buildToolDefinitionsAndRoutes(from: serverTools)
    }

    static func buildToolDefinitionsAndRoutes(
        from serverTools: [(server: MCPServerConfig, tools: [MCPToolInfo])]
    ) -> (definitions: [ToolDefinition], routes: ToolRouteSnapshot) {
        var newRoutes: [String: ToolRoute] = [:]
        var definitions: [ToolDefinition] = []

        for entry in serverTools {
            let server = entry.server
            for tool in entry.tools {
                if server.disabledTools.contains(tool.name) { continue }
                let functionName = Self.disambiguatedFunctionName(
                    serverID: server.id,
                    toolName: tool.name,
                    existing: newRoutes
                )
                newRoutes[functionName] = ToolRoute(server: server, toolName: tool.name)

                definitions.append(
                    ToolDefinition(
                        id: "\(server.id):\(tool.name)",
                        name: functionName,
                        description: tool.description,
                        parameters: tool.inputSchema,
                        source: .mcp(serverID: server.id)
                    )
                )
            }
        }

        return (definitions, ToolRouteSnapshot(routes: newRoutes))
    }

    func executeTool(functionName: String, arguments: [String: AnyCodable], routes: ToolRouteSnapshot) async throws -> MCPToolCallResult {
        guard let route = routes.routes[functionName] else {
            throw MCPHubError.unknownTool(functionName)
        }

        return try await withClient(for: route.server) { client in
            try await client.callTool(name: route.toolName, arguments: arguments)
        }
    }

    private func withClient<T>(for server: MCPServerConfig, operation: (MCPClient) async throws -> T) async throws -> T {
        if server.lifecycle.isPersistent {
            let client = await clientForServer(server)
            return try await operation(client)
        }

        let client = MCPClient(config: server)
        do {
            let result = try await operation(client)
            await client.stop()
            return result
        } catch {
            await client.stop()
            throw error
        }
    }

    private func clientForServer(_ server: MCPServerConfig) async -> MCPClient {
        if let existing = clients[server.id],
           let existingConfig = clientConfigs[server.id],
           isSameConnectionConfig(existingConfig, server) {
            clientConfigs[server.id] = server
            return existing
        }

        if let existing = clients[server.id] {
            await existing.stop()
        }

        let client = MCPClient(config: server)
        clients[server.id] = client
        clientConfigs[server.id] = server
        return client
    }

    private func isSameConnectionConfig(_ lhs: MCPServerConfig, _ rhs: MCPServerConfig) -> Bool {
        lhs.transport == rhs.transport
            && lhs.lifecycle == rhs.lifecycle
    }

    /// Build a function name, then disambiguate if it collides with an existing route.
    private static func disambiguatedFunctionName(
        serverID: String,
        toolName: String,
        existing: [String: ToolRoute]
    ) -> String {
        let candidate = makeFunctionName(serverID: serverID, toolName: toolName)
        if existing[candidate] == nil {
            return candidate
        }
        // Collision — append incrementing suffix until unique.
        for suffix in 2...99 {
            let suffixStr = "_\(suffix)"
            let maxBase = functionNameMaxLength - suffixStr.count
            let base = candidate.count > maxBase ? String(candidate.prefix(maxBase)) : candidate
            let disambiguated = "\(base)\(suffixStr)"
            if existing[disambiguated] == nil {
                return disambiguated
            }
        }
        // Extremely unlikely fallback — still enforce 64-char limit
        let uuidSuffix = "_\(UUID().uuidString.prefix(4))"
        let maxBase = functionNameMaxLength - uuidSuffix.count
        let base = candidate.count > maxBase ? String(candidate.prefix(maxBase)) : candidate
        return "\(base)\(uuidSuffix)"
    }

    static func makeFunctionName(serverID: String, toolName: String) -> String {
        let raw = "\(serverID)\(functionNameSeparator)\(toolName)"
        if raw.count <= functionNameMaxLength {
            return raw
        }

        let shortID = String(serverID.prefix(functionNameShortServerIDLength))
        let shortened = "\(shortID)\(functionNameSeparator)\(toolName)"
        if shortened.count <= functionNameMaxLength {
            return shortened
        }

        let remaining = max(1, functionNameMaxLength - (shortID.count + functionNameSeparator.count))
        let truncatedToolName = String(toolName.prefix(remaining))
        return "\(shortID)\(functionNameSeparator)\(truncatedToolName)"
    }

    struct ToolRoute: Sendable {
        let server: MCPServerConfig
        let toolName: String
    }
}

enum MCPHubError: Error, LocalizedError {
    case unknownTool(String)
    case serverNotConnected(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .serverNotConnected(let serverID):
            return "MCP server not connected: \(serverID)"
        }
    }
}
