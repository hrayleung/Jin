import Foundation

struct AgentToolRouteSnapshot: Sendable {
    private let routes: Set<String>

    init(routes: Set<String>) {
        self.routes = routes
    }

    func contains(functionName: String) -> Bool {
        routes.contains(functionName)
    }

    var isEmpty: Bool { routes.isEmpty }
}

actor AgentToolHub {
    static let shared = AgentToolHub()

    static let serverID = "agent"
    static let functionNamePrefix = "\(serverID)__"
    static let shellExecuteFunctionName = "\(functionNamePrefix)shell_execute"
    static let fileReadFunctionName = "\(functionNamePrefix)file_read"
    static let fileWriteFunctionName = "\(functionNamePrefix)file_write"
    static let fileEditFunctionName = "\(functionNamePrefix)file_edit"
    static let globSearchFunctionName = "\(functionNamePrefix)glob_search"
    static let grepSearchFunctionName = "\(functionNamePrefix)grep_search"

    static func isAgentFunctionName(_ functionName: String) -> Bool {
        functionName.hasPrefix(functionNamePrefix)
    }

    struct PreparedShellExecution: Sendable {
        let rawCommand: String
        let rewrittenCommand: String
        let workingDirectory: String?
    }

    // MARK: - Tool Definitions

    func toolDefinitions(
        for controls: GenerationControls
    ) -> (definitions: [ToolDefinition], routes: AgentToolRouteSnapshot) {
        guard let agentMode = controls.agentMode, agentMode.enabled else {
            return ([], AgentToolRouteSnapshot(routes: []))
        }
        return AgentToolDefinitionFactory.makeDefinitions(for: agentMode.enabledTools)
    }

    // MARK: - Tool Execution

    func executeTool(
        functionName: String,
        arguments: [String: AnyCodable],
        routes: AgentToolRouteSnapshot,
        controls: AgentModeControls,
        preparedShellExecution: PreparedShellExecution? = nil
    ) async throws -> MCPToolCallResult {
        guard routes.contains(functionName: functionName) else {
            throw LLMError.invalidRequest(message: "Unknown agent tool: \(functionName)")
        }

        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case AgentToolNames.shellExecute:
            return try await executeShell(raw, controls: controls, prepared: preparedShellExecution)
        case AgentToolNames.fileRead:
            return try executeFileRead(raw, controls: controls)
        case AgentToolNames.fileWrite:
            return try executeFileWrite(raw, controls: controls)
        case AgentToolNames.fileEdit:
            return try executeFileEdit(raw, controls: controls)
        case AgentToolNames.globSearch:
            return try await executeGlobSearch(raw, controls: controls)
        case AgentToolNames.grepSearch:
            return try await executeGrepSearch(raw, controls: controls)
        default:
            throw LLMError.invalidRequest(message: "Unknown agent tool: \(functionName)")
        }
    }

    // MARK: - Execution Implementations

    func prepareShellExecution(
        arguments: [String: AnyCodable],
        controls: AgentModeControls
    ) async throws -> PreparedShellExecution {
        let raw = arguments.mapValues { $0.value }
        return try await prepareShellExecution(raw, controls: controls)
    }

    private func executeShell(
        _ args: [String: Any],
        controls: AgentModeControls,
        prepared: PreparedShellExecution?
    ) async throws -> MCPToolCallResult {
        let preparedShell: PreparedShellExecution
        if let prepared {
            preparedShell = prepared
        } else {
            preparedShell = try await prepareShellExecution(args, controls: controls)
        }
        guard preparedShell.rewrittenCommand.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("rtk ") else {
            throw LLMError.invalidRequest(
                message: "RTK rewrite produced an unsafe shell command. Refusing to execute: \(preparedShell.rewrittenCommand)"
            )
        }
        let result = try await RTKRuntimeSupport.executeRewrittenShellCommand(
            preparedShell.rewrittenCommand,
            workingDirectory: preparedShell.workingDirectory,
            timeout: TimeInterval(controls.commandTimeoutSeconds),
            maxOutputBytes: controls.maxOutputBytes
        )
        return MCPToolCallResult(
            text: result.text,
            isError: result.isError,
            rawOutputPath: result.rawOutputPath
        )
    }

    private func executeFileRead(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let path = AgentToolArgumentParser.stringArg(args, keys: ["path", "file", "file_path", "filePath"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'path'", isError: true)
        }

        let offset = AgentToolArgumentParser.intArg(args, keys: ["offset", "line_offset", "start_line"])
        let limit = AgentToolArgumentParser.intArg(args, keys: ["limit", "line_count", "max_lines"])

        let result = try AgentFileOperations.readFile(
            path: path,
            offset: offset,
            limit: limit,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false, rawOutputPath: nil)
    }

    private func executeFileWrite(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let path = AgentToolArgumentParser.stringArg(args, keys: ["path", "file", "file_path", "filePath"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'path'", isError: true)
        }

        guard let content = AgentToolArgumentParser.stringArg(args, keys: ["content", "text", "data"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'content'", isError: true)
        }

        let result = try AgentFileOperations.writeFile(
            path: path,
            content: content,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false, rawOutputPath: nil)
    }

    private func executeFileEdit(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let path = AgentToolArgumentParser.stringArg(args, keys: ["path", "file", "file_path", "filePath"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'path'", isError: true)
        }

        guard let oldText = AgentToolArgumentParser.stringArg(args, keys: ["old_text", "oldText", "old_string", "search"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'old_text'", isError: true)
        }

        guard let newText = AgentToolArgumentParser.stringArg(args, keys: ["new_text", "newText", "new_string", "replace"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'new_text'", isError: true)
        }

        let result = try AgentFileOperations.editFile(
            path: path,
            oldText: oldText,
            newText: newText,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false, rawOutputPath: nil)
    }

    private func executeGlobSearch(
        _ args: [String: Any],
        controls: AgentModeControls
    ) async throws -> MCPToolCallResult {
        guard let pattern = AgentToolArgumentParser.stringArg(args, keys: ["pattern", "glob"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'pattern'", isError: true)
        }

        let directory = AgentToolArgumentParser.stringArg(args, keys: ["path", "directory", "dir"]) ?? "."
        let result = try await RTKRuntimeSupport.executeHelperCommand(
            arguments: ["find", pattern, directory],
            workingDirectory: controls.workingDirectory,
            timeout: TimeInterval(controls.commandTimeoutSeconds),
            maxOutputBytes: controls.maxOutputBytes
        )

        return MCPToolCallResult(
            text: result.text,
            isError: result.isError,
            rawOutputPath: result.rawOutputPath
        )
    }

    private func executeGrepSearch(
        _ args: [String: Any],
        controls: AgentModeControls
    ) async throws -> MCPToolCallResult {
        guard let pattern = AgentToolArgumentParser.stringArg(args, keys: ["pattern", "regex", "query"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'pattern'", isError: true)
        }

        let path = AgentToolArgumentParser.stringArg(args, keys: ["path", "directory", "dir"]) ?? "."
        let include = AgentToolArgumentParser.stringArg(args, keys: ["include", "glob", "file_pattern"])
        var helperArguments = ["grep", pattern, path]
        if let include, !include.isEmpty {
            helperArguments.append(contentsOf: ["--glob", include])
        }

        let result = try await RTKRuntimeSupport.executeHelperCommand(
            arguments: helperArguments,
            workingDirectory: controls.workingDirectory,
            timeout: TimeInterval(controls.commandTimeoutSeconds),
            maxOutputBytes: controls.maxOutputBytes
        )

        let isNoMatchSummary = result.exitCode == 1
            && result.text.lowercased().contains("0 matches")
        return MCPToolCallResult(
            text: result.text,
            isError: result.isError && !isNoMatchSummary,
            rawOutputPath: result.rawOutputPath
        )
    }

    private func prepareShellExecution(
        _ args: [String: Any],
        controls: AgentModeControls
    ) async throws -> PreparedShellExecution {
        guard let command = AgentToolArgumentParser.stringArg(args, keys: ["command", "cmd"]) else {
            throw LLMError.invalidRequest(message: "Agent shell execution requires a non-empty `command`.")
        }

        let cwd = AgentToolArgumentParser.stringArg(args, keys: ["working_directory", "workingDirectory", "cwd"])
            ?? controls.workingDirectory
        let rewrittenCommand = try await RTKRuntimeSupport.prepareShellCommand(command)
        return PreparedShellExecution(
            rawCommand: command,
            rewrittenCommand: rewrittenCommand,
            workingDirectory: cwd
        )
    }

}
