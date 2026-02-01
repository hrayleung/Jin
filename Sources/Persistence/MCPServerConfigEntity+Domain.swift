import Foundation

extension MCPServerConfigEntity {
    func toConfig() -> MCPServerConfig {
        let args: [String] = (try? JSONDecoder().decode([String].self, from: argsData)) ?? []
        let env: [String: String] = envData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]

        return MCPServerConfig(
            id: id,
            name: name,
            command: command,
            args: args,
            env: env,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: isLongRunning
        )
    }

    func setArgs(_ args: [String]) {
        argsData = (try? JSONEncoder().encode(args)) ?? Data()
    }

    func setEnv(_ env: [String: String]) {
        envData = (try? JSONEncoder().encode(env))
    }
}

