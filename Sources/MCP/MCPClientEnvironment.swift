import Collections
import Foundation

// MARK: - Command Parsing, Environment Setup, Node Isolation

extension MCPClient {
    func parseCommandAndArgs(stdio: MCPStdioTransportConfig) throws -> (command: String, args: [String]) {
        let trimmedCommandLine = stdio.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommandLine.isEmpty else {
            throw MCPClientError.invalidCommand
        }

        let tokens: [String]
        do {
            tokens = try CommandLineTokenizer.tokenize(trimmedCommandLine)
        } catch {
            throw MCPClientError.invalidCommand
        }

        guard let command = tokens.first else {
            throw MCPClientError.invalidCommand
        }

        var args = Array(tokens.dropFirst())
        if !stdio.args.isEmpty {
            args.append(contentsOf: stdio.args)
        }

        return (command, args)
    }

    func makeProcessEnvironment(stdio: MCPStdioTransportConfig, command: String) throws -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        for (key, value) in stdio.env {
            env[key] = value
        }

        env["PATH"] = mergedPath(existing: env["PATH"])
        try applyNodeIsolationIfNeeded(stdio: stdio, command: command, environment: &env)
        return env
    }

    func mergedPath(existing: String?) -> String {
        let existingComponents = (existing ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        var merged = OrderedSet<String>()

        func append(_ entry: String) {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            merged.append(trimmed)
        }

        for entry in existingComponents {
            append(entry)
        }

        for entry in Self.defaultPathEntries {
            append(entry)
        }

        for entry in additionalPathEntries() {
            append(entry)
        }

        return merged.elements.joined(separator: ":")
    }

    func applyNodeIsolationIfNeeded(
        stdio: MCPStdioTransportConfig,
        command: String,
        environment: inout [String: String]
    ) throws {
        let base = (command as NSString).lastPathComponent.lowercased()
        let isNodeLauncher = ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
        guard isNodeLauncher else { return }

        let root = try nodeIsolationRoot()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let npmCache = root.appendingPathComponent("npm-cache", isDirectory: true)
        let npmPrefix = root.appendingPathComponent("npm-prefix", isDirectory: true)
        let npmrc = home.appendingPathComponent(".npmrc", isDirectory: false)

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: npmPrefix, withIntermediateDirectories: true)

        if stdio.env["HOME"] == nil {
            environment["HOME"] = home.path
        }

        if stdio.env["NPM_CONFIG_USERCONFIG"] == nil && stdio.env["npm_config_userconfig"] == nil {
            let inherited = safeNpmrcEntriesToInherit(from: environment)
            try ensureIsolatedNpmrc(at: npmrc, npmPrefix: npmPrefix, npmCache: npmCache, inherited: inherited)

            environment["NPM_CONFIG_USERCONFIG"] = npmrc.path
            environment["npm_config_userconfig"] = npmrc.path
        }

        if stdio.env["NPM_CONFIG_CACHE"] == nil && stdio.env["npm_config_cache"] == nil {
            environment["NPM_CONFIG_CACHE"] = npmCache.path
            environment["npm_config_cache"] = npmCache.path
        }

        if stdio.env["NPM_CONFIG_PREFIX"] == nil && stdio.env["npm_config_prefix"] == nil {
            environment["NPM_CONFIG_PREFIX"] = npmPrefix.path
            environment["npm_config_prefix"] = npmPrefix.path
        }
    }

    private func safeNpmrcEntriesToInherit(from environment: [String: String]) -> [String: String] {
        guard let url = userNpmrcURL(from: environment) else { return [:] }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return NPMRCUtils.safeEntriesToInherit(from: contents)
    }

    private func userNpmrcURL(from environment: [String: String]) -> URL? {
        if let path = environment["NPM_CONFIG_USERCONFIG"] ?? environment["npm_config_userconfig"] {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let expanded = (trimmed as NSString).expandingTildeInPath
                return URL(fileURLWithPath: expanded)
            }
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npmrc")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func ensureIsolatedNpmrc(
        at url: URL,
        npmPrefix: URL,
        npmCache: URL,
        inherited: [String: String]
    ) throws {
        let desiredAssignments: [String: String] = [
            "prefix": npmPrefix.path,
            "cache": npmCache.path,
            "fund": "false",
            "update-notifier": "false",
            "progress": "false",
        ]

        let existingContents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let existingAssignments = NPMRCUtils.parseAssignments(from: existingContents)

        var linesToAppend: [String] = []

        for (key, value) in desiredAssignments {
            if existingAssignments[key] != value {
                linesToAppend.append("\(key)=\(value)")
            }
        }

        for (key, value) in inherited.sorted(by: { $0.key < $1.key }) {
            if existingAssignments[key] == nil {
                linesToAppend.append("\(key)=\(value)")
            }
        }

        guard !linesToAppend.isEmpty else { return }

        var newContents = existingContents
        if newContents.isEmpty {
            newContents = "# Generated by Jin (MCP node isolation)\n"
        } else if !newContents.hasSuffix("\n") {
            newContents.append("\n")
        }

        newContents.append(linesToAppend.joined(separator: "\n"))
        newContents.append("\n")

        do {
            try newContents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw MCPClientError.environmentSetupFailed(message: "Failed to write \(url.path): \(error.localizedDescription)")
        }
    }

    func nodeIsolationRoot() throws -> URL {
        let safeID = sanitizePathComponent(config.id)
        let base: URL
        do {
            base = try AppDataLocations.mcpRuntimeDirectoryURL()
        } catch {
            throw MCPClientError.environmentSetupFailed(message: "Unable to locate Application Support directory.")
        }

        let root = base
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent(safeID, isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func sanitizePathComponent(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID().uuidString }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var result = ""
        result.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }

        return result.isEmpty ? UUID().uuidString : result
    }

    func nodeEnvironmentDiagnostics(from environment: [String: String]) -> NodeEnvironmentDiagnostics? {
        guard let npmUserConfig = environment["NPM_CONFIG_USERCONFIG"] ?? environment["npm_config_userconfig"] else {
            return nil
        }

        let home = environment["HOME"]
        let npmCache = environment["NPM_CONFIG_CACHE"] ?? environment["npm_config_cache"]
        let npmPrefix = environment["NPM_CONFIG_PREFIX"] ?? environment["npm_config_prefix"]
        return NodeEnvironmentDiagnostics(home: home, npmUserConfig: npmUserConfig, npmCache: npmCache, npmPrefix: npmPrefix)
    }

    func resolveExecutableURL(command: String, environment: [String: String], workingDirectory: URL) -> URL? {
        let expanded = (command as NSString).expandingTildeInPath

        if expanded.contains("/") {
            let path: String
            if expanded.hasPrefix("/") {
                path = expanded
            } else {
                path = workingDirectory
                    .appendingPathComponent(expanded)
                    .path
            }

            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }

        let pathValue = environment["PATH"] ?? ""
        for dir in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = "\(dir)/\(expanded)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    func defaultWorkingDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    func workingDirectoryForProcess(command: String) throws -> URL {
        let base = (command as NSString).lastPathComponent.lowercased()
        let isNodeLauncher = ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
        guard isNodeLauncher else { return defaultWorkingDirectory() }

        // Avoid treating the user's ~/.npmrc as a project-level .npmrc by running in a clean directory.
        return try nodeIsolationRoot()
    }

    func additionalPathEntries() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        var candidates: [String] = [
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".asdf/shims").path,
            home.appendingPathComponent(".mise/shims").path,
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent("bin").path,
        ]

        candidates.append(contentsOf: nvmBinPaths(home: home))
        candidates.append(contentsOf: fnmBinPaths(home: home))

        return candidates.filter(isExistingDirectory)
    }

    private func nvmBinPaths(home: URL) -> [String] {
        let root = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.map { $0.appendingPathComponent("bin", isDirectory: true).path }
    }

    private func fnmBinPaths(home: URL) -> [String] {
        let root = home.appendingPathComponent(".fnm/node-versions", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.map { $0.appendingPathComponent("installation/bin", isDirectory: true).path }
    }

    func isExistingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
