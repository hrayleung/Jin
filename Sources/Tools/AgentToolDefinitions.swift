import Foundation

enum AgentToolNames {
    static let shellExecute = AgentToolHub.shellExecuteFunctionName
    static let fileRead = AgentToolHub.fileReadFunctionName
    static let fileWrite = AgentToolHub.fileWriteFunctionName
    static let fileEdit = AgentToolHub.fileEditFunctionName
    static let globSearch = AgentToolHub.globSearchFunctionName
    static let grepSearch = AgentToolHub.grepSearchFunctionName
}

enum AgentToolDefinitionFactory {
    static func makeDefinitions(
        for tools: AgentEnabledTools
    ) -> (definitions: [ToolDefinition], routes: AgentToolRouteSnapshot) {
        var definitions: [ToolDefinition] = []
        var routeNames: Set<String> = []

        if tools.shellExecute {
            definitions.append(shellExecuteDefinition)
            routeNames.insert(AgentToolNames.shellExecute)
        }

        if tools.fileRead {
            definitions.append(fileReadDefinition)
            routeNames.insert(AgentToolNames.fileRead)
        }

        if tools.fileWrite {
            definitions.append(fileWriteDefinition)
            routeNames.insert(AgentToolNames.fileWrite)
        }

        if tools.fileEdit {
            definitions.append(fileEditDefinition)
            routeNames.insert(AgentToolNames.fileEdit)
        }

        if tools.globSearch {
            definitions.append(globSearchDefinition)
            routeNames.insert(AgentToolNames.globSearch)
        }

        if tools.grepSearch {
            definitions.append(grepSearchDefinition)
            routeNames.insert(AgentToolNames.grepSearch)
        }

        return (definitions, AgentToolRouteSnapshot(routes: routeNames))
    }

    private static var shellExecuteDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:shell_execute",
            name: AgentToolNames.shellExecute,
            description: "Execute a shell command only when the bundled RTK helper can rewrite it to a supported RTK workflow. Prefer dedicated tools for file reads and searches.",
            parameters: ParameterSchema(
                properties: [
                    "command": PropertySchema(type: "string", description: "A shell command that RTK can rewrite, such as git/cargo/npm/pytest/go/docker/kubectl workflows."),
                    "working_directory": PropertySchema(type: "string", description: "Optional working directory for the command. Defaults to the configured agent working directory.")
                ],
                required: ["command"]
            ),
            source: .builtin
        )
    }

    private static var fileReadDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:file_read",
            name: AgentToolNames.fileRead,
            description: "Read a file with precise line-numbered output. Use this instead of shell cat/head/tail when you need exact edit context.",
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

    private static var fileWriteDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:file_write",
            name: AgentToolNames.fileWrite,
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

    private static var fileEditDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:file_edit",
            name: AgentToolNames.fileEdit,
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

    private static var globSearchDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:glob_search",
            name: AgentToolNames.globSearch,
            description: "Find files using the bundled RTK helper. Best for compact repo-wide file discovery without executing raw shell find commands.",
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

    private static var grepSearchDefinition: ToolDefinition {
        ToolDefinition(
            id: "agent:grep_search",
            name: AgentToolNames.grepSearch,
            description: "Search file contents using the bundled RTK grep workflow. Returns compact grouped results and supports an optional include glob.",
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
