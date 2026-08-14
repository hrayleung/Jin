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

struct MCPServerToolLoadFailure: Sendable, Equatable {
    let serverID: String
    let serverName: String
    let presentation: MCPErrorPresentation
}

struct MCPToolLoadResult: Sendable {
    let definitions: [ToolDefinition]
    let routes: ToolRouteSnapshot
    let failures: [MCPServerToolLoadFailure]
}

actor MCPHub {
    static let shared = MCPHub()
    static let functionNameSeparator = "__"
    static let functionNameMaxLength = 64
    private static let functionNameShortServerIDLength = 8

    private var clients: [String: MCPClient] = [:]
    private var clientConfigs: [String: MCPServerConfig] = [:]
    /// Servers shut down by `shutdown(serverID:)`, kept so a stale route cannot restart
    /// one. Cleared as soon as the live configuration mentions the ID again.
    private var shutDownServerIDs: Set<String> = []

    func listTools(for server: MCPServerConfig) async throws -> [MCPToolInfo] {
        noteServerIsConfigured(server.id)
        return try await withClient(for: server) { client in
            try await client.listTools()
        }
    }

    func toolDefinitions(for servers: [MCPServerConfig]) async -> MCPToolLoadResult {
        let enabledServers = servers.filter(\.isEnabled)
        // These come straight from the live configuration, so any of them that were
        // tombstoned by a previous delete clearly exist again.
        for server in enabledServers { noteServerIsConfigured(server.id) }

        let loaded = await withTaskGroup(
            of: ServerToolLoad.self,
            returning: (tools: [(server: MCPServerConfig, tools: [MCPToolInfo])], failures: [MCPServerToolLoadFailure]).self
        ) { group in
            for server in enabledServers {
                group.addTask {
                    do {
                        let tools = try await self.withClient(for: server) { client in
                            try await client.listTools()
                        }
                        return .success(server: server, tools: tools)
                    } catch {
                        return .failure(
                            MCPServerToolLoadFailure(
                                serverID: server.id,
                                serverName: server.name,
                                presentation: MCPErrorPresentation.make(from: error)
                            )
                        )
                    }
                }
            }

            var tools: [(server: MCPServerConfig, tools: [MCPToolInfo])] = []
            var failures: [MCPServerToolLoadFailure] = []
            for await result in group {
                switch result {
                case .success(let server, let serverTools):
                    tools.append((server, serverTools))
                case .failure(let failure):
                    failures.append(failure)
                }
            }
            return (tools, failures)
        }

        // Preserve original server ordering for deterministic function name disambiguation
        let serverOrder = Dictionary(uniqueKeysWithValues: enabledServers.enumerated().map { ($1.id, $0) })
        let sorted = loaded.tools.sorted { (serverOrder[$0.server.id] ?? 0) < (serverOrder[$1.server.id] ?? 0) }
        let built = Self.buildToolDefinitionsAndRoutes(from: sorted)
        let sortedFailures = loaded.failures.sorted { (serverOrder[$0.serverID] ?? 0) < (serverOrder[$1.serverID] ?? 0) }

        return MCPToolLoadResult(definitions: built.definitions, routes: built.routes, failures: sortedFailures)
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
                        description: tool.modelFacingDescription,
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

    /// Stop and evict a persistent server's client. Without this a deleted or disabled
    /// server keeps its child process alive until the app restarts.
    ///
    /// The server ID is also tombstoned, because a turn already in flight still holds a
    /// `ToolRouteSnapshot` containing the old config — without this, its next tool call
    /// would find no cached client and cheerfully spawn the process again.
    func shutdown(serverID: String) async {
        shutDownServerIDs.insert(serverID)
        clientConfigs.removeValue(forKey: serverID)
        guard let client = clients.removeValue(forKey: serverID) else { return }
        await client.stop()
    }

    /// Clears the tombstone for a server that is present in the live configuration
    /// again, so deleting and re-adding the same ID works.
    private func noteServerIsConfigured(_ serverID: String) {
        shutDownServerIDs.remove(serverID)
    }

    private func withClient<T>(for server: MCPServerConfig, operation: (MCPClient) async throws -> T) async throws -> T {
        guard !shutDownServerIDs.contains(server.id) else {
            throw MCPHubError.serverNotConnected(server.id)
        }

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

        let stale = clients.removeValue(forKey: server.id)

        let client = MCPClient(config: server)
        clients[server.id] = client
        clientConfigs[server.id] = server

        if let stale {
            await stale.stop()
        }

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

    private enum ServerToolLoad: Sendable {
        case success(server: MCPServerConfig, tools: [MCPToolInfo])
        case failure(MCPServerToolLoadFailure)
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
