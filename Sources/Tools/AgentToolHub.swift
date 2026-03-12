import Foundation

struct AgentToolRouteSnapshot: Sendable {
    fileprivate let routes: Set<String>

    func contains(functionName: String) -> Bool {
        routes.contains(functionName)
    }

    var isEmpty: Bool { routes.isEmpty }
}

actor AgentToolHub {
    static let shared = AgentToolHub()

    static let serverID = "agent"
    static let functionNamePrefix = "\(serverID)__"

    static func isAgentFunctionName(_ functionName: String) -> Bool {
        functionName.hasPrefix(functionNamePrefix)
    }

    // MARK: - Tool Names

    private enum ToolName {
        static let shellExecute = "\(AgentToolHub.functionNamePrefix)shell_execute"
        static let fileRead = "\(AgentToolHub.functionNamePrefix)file_read"
        static let fileWrite = "\(AgentToolHub.functionNamePrefix)file_write"
        static let fileEdit = "\(AgentToolHub.functionNamePrefix)file_edit"
        static let globSearch = "\(AgentToolHub.functionNamePrefix)glob_search"
        static let grepSearch = "\(AgentToolHub.functionNamePrefix)grep_search"
    }

    // MARK: - Tool Definitions

    func toolDefinitions(
        for controls: GenerationControls
    ) -> (definitions: [ToolDefinition], routes: AgentToolRouteSnapshot) {
        guard let agentMode = controls.agentMode, agentMode.enabled else {
            return ([], AgentToolRouteSnapshot(routes: []))
        }

        var definitions: [ToolDefinition] = []
        var routeNames: Set<String> = []
        let tools = agentMode.enabledTools

        if tools.shellExecute {
            definitions.append(shellExecuteDefinition)
            routeNames.insert(ToolName.shellExecute)
        }

        if tools.fileRead {
            definitions.append(fileReadDefinition)
            routeNames.insert(ToolName.fileRead)
        }

        if tools.fileWrite {
            definitions.append(fileWriteDefinition)
            routeNames.insert(ToolName.fileWrite)
        }

        if tools.fileEdit {
            definitions.append(fileEditDefinition)
            routeNames.insert(ToolName.fileEdit)
        }

        if tools.globSearch {
            definitions.append(globSearchDefinition)
            routeNames.insert(ToolName.globSearch)
        }

        if tools.grepSearch {
            definitions.append(grepSearchDefinition)
            routeNames.insert(ToolName.grepSearch)
        }

        return (definitions, AgentToolRouteSnapshot(routes: routeNames))
    }

    // MARK: - Tool Execution

    func executeTool(
        functionName: String,
        arguments: [String: AnyCodable],
        routes: AgentToolRouteSnapshot,
        controls: AgentModeControls
    ) async throws -> MCPToolCallResult {
        guard routes.contains(functionName: functionName) else {
            throw LLMError.invalidRequest(message: "Unknown agent tool: \(functionName)")
        }

        let raw = arguments.mapValues { $0.value }

        switch functionName {
        case ToolName.shellExecute:
            return try await executeShell(raw, controls: controls)
        case ToolName.fileRead:
            return try executeFileRead(raw, controls: controls)
        case ToolName.fileWrite:
            return try executeFileWrite(raw, controls: controls)
        case ToolName.fileEdit:
            return try executeFileEdit(raw, controls: controls)
        case ToolName.globSearch:
            return try executeGlobSearch(raw, controls: controls)
        case ToolName.grepSearch:
            return try executeGrepSearch(raw, controls: controls)
        default:
            throw LLMError.invalidRequest(message: "Unknown agent tool: \(functionName)")
        }
    }

    // MARK: - Execution Implementations

    private func executeShell(
        _ args: [String: Any],
        controls: AgentModeControls
    ) async throws -> MCPToolCallResult {
        guard let command = stringArg(args, keys: ["command", "cmd"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'command'", isError: true)
        }

        let cwd = stringArg(args, keys: ["working_directory", "workingDirectory", "cwd"])
            ?? controls.workingDirectory

        let result = try await AgentShellExecutor.execute(
            command: command,
            workingDirectory: cwd,
            timeout: TimeInterval(controls.commandTimeoutSeconds),
            maxOutputBytes: controls.maxOutputBytes
        )

        var output = ""
        if !result.stdout.isEmpty {
            output += result.stdout
        }
        if !result.stderr.isEmpty {
            if !output.isEmpty { output += "\n\n" }
            output += "[stderr]\n\(result.stderr)"
        }
        if output.isEmpty {
            output = "(no output)"
        }

        output += "\n\n[exit code: \(result.exitCode), duration: \(String(format: "%.1f", result.durationSeconds))s]"

        return MCPToolCallResult(text: output, isError: result.exitCode != 0)
    }

    private func executeFileRead(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let path = stringArg(args, keys: ["path", "file", "file_path", "filePath"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'path'", isError: true)
        }

        let offset = intArg(args, keys: ["offset", "line_offset", "start_line"])
        let limit = intArg(args, keys: ["limit", "line_count", "max_lines"])

        let result = try AgentFileOperations.readFile(
            path: path,
            offset: offset,
            limit: limit,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false)
    }

    private func executeFileWrite(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let path = stringArg(args, keys: ["path", "file", "file_path", "filePath"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'path'", isError: true)
        }

        guard let content = stringArg(args, keys: ["content", "text", "data"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'content'", isError: true)
        }

        let result = try AgentFileOperations.writeFile(
            path: path,
            content: content,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false)
    }

    private func executeFileEdit(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let path = stringArg(args, keys: ["path", "file", "file_path", "filePath"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'path'", isError: true)
        }

        guard let oldText = stringArg(args, keys: ["old_text", "oldText", "old_string", "search"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'old_text'", isError: true)
        }

        guard let newText = stringArg(args, keys: ["new_text", "newText", "new_string", "replace"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'new_text'", isError: true)
        }

        let result = try AgentFileOperations.editFile(
            path: path,
            oldText: oldText,
            newText: newText,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false)
    }

    private func executeGlobSearch(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let pattern = stringArg(args, keys: ["pattern", "glob"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'pattern'", isError: true)
        }

        let directory = stringArg(args, keys: ["path", "directory", "dir"])

        let result = try AgentFileOperations.globSearch(
            pattern: pattern,
            directory: directory,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false)
    }

    private func executeGrepSearch(
        _ args: [String: Any],
        controls: AgentModeControls
    ) throws -> MCPToolCallResult {
        guard let pattern = stringArg(args, keys: ["pattern", "regex", "query"]) else {
            return MCPToolCallResult(text: "Error: missing required parameter 'pattern'", isError: true)
        }

        let path = stringArg(args, keys: ["path", "directory", "dir"])
        let include = stringArg(args, keys: ["include", "glob", "file_pattern"])

        let result = try AgentFileOperations.grepSearch(
            pattern: pattern,
            path: path,
            include: include,
            workingDirectory: controls.workingDirectory
        )

        return MCPToolCallResult(text: result, isError: false)
    }

    // MARK: - Argument Helpers

    private func stringArg(_ args: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func intArg(_ args: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = args[key] as? Int { return value }
            if let value = args[key] as? Double { return Int(value) }
            if let value = args[key] as? String, let intVal = Int(value) { return intVal }
        }
        return nil
    }

    // MARK: - Tool Definition Schemas

    private var shellExecuteDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:shell_execute",
            name: ToolName.shellExecute,
            description: "Execute a shell command via /bin/zsh. Returns stdout, stderr, and exit code. Use for running build commands, scripts, or CLI tools.",
            parameters: ParameterSchema(
                properties: [
                    "command": PropertySchema(type: "string", description: "The shell command to execute."),
                    "working_directory": PropertySchema(type: "string", description: "Optional working directory for the command. Defaults to the configured agent working directory.")
                ],
                required: ["command"]
            ),
            source: .builtin
        )
    }

    private var fileReadDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:file_read",
            name: ToolName.fileRead,
            description: "Read a file and return its contents with line numbers. Supports reading specific line ranges via offset and limit parameters.",
            parameters: ParameterSchema(
                properties: [
                    "path": PropertySchema(type: "string", description: "File path to read. Relative paths are resolved against the working directory."),
                    "offset": PropertySchema(type: "integer", description: "Start reading from this line number (1-based). Defaults to 1."),
                    "limit": PropertySchema(type: "integer", description: "Maximum number of lines to read. Defaults to reading the entire file.")
                ],
                required: ["path"]
            ),
            source: .builtin
        )
    }

    private var fileWriteDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:file_write",
            name: ToolName.fileWrite,
            description: "Write content to a file, creating it and any intermediate directories if they don't exist. Overwrites existing files.",
            parameters: ParameterSchema(
                properties: [
                    "path": PropertySchema(type: "string", description: "File path to write. Relative paths are resolved against the working directory."),
                    "content": PropertySchema(type: "string", description: "The content to write to the file.")
                ],
                required: ["path", "content"]
            ),
            source: .builtin
        )
    }

    private var fileEditDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:file_edit",
            name: ToolName.fileEdit,
            description: "Find and replace text in a file. The old_text must appear exactly once in the file to avoid ambiguity.",
            parameters: ParameterSchema(
                properties: [
                    "path": PropertySchema(type: "string", description: "File path to edit. Relative paths are resolved against the working directory."),
                    "old_text": PropertySchema(type: "string", description: "The exact text to find in the file. Must match exactly once."),
                    "new_text": PropertySchema(type: "string", description: "The text to replace the old_text with.")
                ],
                required: ["path", "old_text", "new_text"]
            ),
            source: .builtin
        )
    }

    private var globSearchDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:glob_search",
            name: ToolName.globSearch,
            description: "Find files matching a glob pattern. Supports *, **, and ? wildcards. Returns matching file paths relative to the search directory.",
            parameters: ParameterSchema(
                properties: [
                    "pattern": PropertySchema(type: "string", description: "Glob pattern to match files (e.g., \"**/*.swift\", \"src/**/*.ts\")."),
                    "path": PropertySchema(type: "string", description: "Directory to search in. Defaults to the working directory.")
                ],
                required: ["pattern"]
            ),
            source: .builtin
        )
    }

    private var grepSearchDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:grep_search",
            name: ToolName.grepSearch,
            description: "Search file contents using a regex pattern (grep -rn). Returns matching lines with file paths and line numbers.",
            parameters: ParameterSchema(
                properties: [
                    "pattern": PropertySchema(type: "string", description: "Regex pattern to search for."),
                    "path": PropertySchema(type: "string", description: "File or directory to search in. Defaults to the working directory."),
                    "include": PropertySchema(type: "string", description: "Optional glob pattern to filter files (e.g., \"*.swift\").")
                ],
                required: ["pattern"]
            ),
            source: .builtin
        )
    }
}
