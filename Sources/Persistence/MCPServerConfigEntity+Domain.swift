import Foundation

extension MCPServerConfigEntity {
    func toConfig() -> MCPServerConfig {
        let transport = transportConfig()
        let lifecycle = MCPLifecyclePolicy(rawValue: lifecycleRaw) ?? (isLongRunning ? .persistent : .ephemeral)

        return MCPServerConfig(
            id: id,
            name: name,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            lifecycle: lifecycle,
            transport: transport,
            disabledTools: disabledTools()
        )
    }

    func apply(config: MCPServerConfig) {
        id = config.id
        name = config.name
        isEnabled = config.isEnabled
        runToolsAutomatically = config.runToolsAutomatically
        lifecycleRaw = config.lifecycle.rawValue
        isLongRunning = config.lifecycle.isPersistent
        setTransport(config.transport)
        setDisabledTools(config.disabledTools)
    }

    var transportKind: MCPTransportKind {
        MCPTransportKind(rawValue: transportKindRaw) ?? transportConfig().kind
    }

    func transportConfig() -> MCPTransportConfig {
        decodedTransport() ?? legacyTransportFallback()
    }

    var transportSummary: String {
        switch transportConfig() {
        case .stdio(let stdio):
            let command = stdio.command.trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? "Command-line (stdio)" : command
        case .http(let http):
            return http.endpoint.absoluteString
        }
    }

    func setTransport(_ transport: MCPTransportConfig) {
        let encoder = JSONEncoder()
        transportKindRaw = transport.kind.rawValue
        transportData = (try? encoder.encode(transport)) ?? Data()

        // Keep legacy stdio fields in sync for temporary compatibility with stale code paths.
        switch transport {
        case .stdio(let stdio):
            command = stdio.command
            argsData = (try? encoder.encode(stdio.args)) ?? Data()
            envData = stdio.env.isEmpty ? nil : (try? encoder.encode(stdio.env))
        case .http:
            command = ""
            argsData = Data()
            envData = nil
        }
    }

    func disabledTools() -> Set<String> {
        disabledToolsData
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            .map(Set.init)
            ?? []
    }

    func setDisabledTools(_ disabled: Set<String>) {
        let sorted = disabled.sorted()
        disabledToolsData = sorted.isEmpty ? nil : (try? JSONEncoder().encode(sorted))
    }

    private func decodedTransport() -> MCPTransportConfig? {
        guard !transportData.isEmpty else { return nil }
        return try? JSONDecoder().decode(MCPTransportConfig.self, from: transportData)
    }

    private func legacyTransportFallback() -> MCPTransportConfig {
        let args: [String] = (try? JSONDecoder().decode([String].self, from: argsData)) ?? []
        let env: [String: String] = envData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return .stdio(
            MCPStdioTransportConfig(
                command: command,
                args: args,
                env: env
            )
        )
    }
}
