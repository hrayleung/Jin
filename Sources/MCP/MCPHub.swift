import Foundation

actor MCPHub {
    static let shared = MCPHub()

    private var clients: [String: MCPClient] = [:]
    private var clientConfigs: [String: MCPServerConfig] = [:]
    private var toolRoutes: [String: ToolRoute] = [:]

    func listTools(for server: MCPServerConfig) async throws -> [MCPToolInfo] {
        try await withClient(for: server) { client in
            try await client.listTools()
        }
    }

    func toolDefinitions(for servers: [MCPServerConfig]) async throws -> [ToolDefinition] {
        toolRoutes.removeAll()

        var definitions: [ToolDefinition] = []

        for server in servers where server.isEnabled {
            let tools = try await withClient(for: server) { client in
                try await client.listTools()
            }

            for tool in tools {
                let functionName = makeFunctionName(serverID: server.id, toolName: tool.name)
                toolRoutes[functionName] = ToolRoute(server: server, toolName: tool.name)

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

        return definitions
    }

    func executeTool(functionName: String, arguments: [String: AnyCodable]) async throws -> MCPToolCallResult {
        guard let route = toolRoutes[functionName] else {
            throw MCPHubError.unknownTool(functionName)
        }

        return try await withClient(for: route.server) { client in
            try await client.callTool(name: route.toolName, arguments: arguments)
        }
    }

    private func withClient<T>(for server: MCPServerConfig, operation: (MCPClient) async throws -> T) async throws -> T {
        if server.isLongRunning {
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
           clientConfigs[server.id] == server {
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

    private func makeFunctionName(serverID: String, toolName: String) -> String {
        let raw = "\(serverID)__\(toolName)"
        if raw.count <= 64 {
            return raw
        }

        let shortID = String(serverID.prefix(8))
        let shortened = "\(shortID)__\(toolName)"
        if shortened.count <= 64 {
            return shortened
        }

        let remaining = max(1, 64 - (shortID.count + 2))
        let truncatedToolName = String(toolName.prefix(remaining))
        return "\(shortID)__\(truncatedToolName)"
    }

    private struct ToolRoute: Sendable {
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
