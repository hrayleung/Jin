import Foundation

extension MCPServerConfigEntity {
    func toConfig() -> MCPServerConfig {
        let args: [String] = (try? JSONDecoder().decode([String].self, from: argsData)) ?? []
        let env: [String: String] = envData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let disabledTools: Set<String> = disabledToolsData
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            .map(Set.init)
            ?? []

        return MCPServerConfig(
            id: id,
            name: name,
            command: command,
            args: args,
            env: env,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: isLongRunning,
            disabledTools: disabledTools
        )
    }

    func setArgs(_ args: [String]) {
        argsData = (try? JSONEncoder().encode(args)) ?? Data()
    }

    func setEnv(_ env: [String: String]) {
        envData = (try? JSONEncoder().encode(env))
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
}
