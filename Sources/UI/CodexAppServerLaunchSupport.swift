import Foundation

enum CodexAppServerLaunchSupport {
    private static let defaultPathEntries: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func mergedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let pathEntries = existingPath
            .split(separator: ":")
            .map { String($0) }

        var merged = pathEntries
        for entry in defaultPathEntries where !merged.contains(entry) {
            merged.append(entry)
        }
        for entry in commonUserPathEntries() where !merged.contains(entry) {
            merged.append(entry)
        }
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    static func resolveCodexExecutable(environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }

        for entry in pathEntries where !entry.isEmpty {
            let path = URL(fileURLWithPath: entry, isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private static func commonUserPathEntries() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.superset/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.claude/bin",
            "\(home)/.opencode/bin",
            "\(home)/.bun/bin",
        ]
    }
}
