import Foundation

// MARK: - Public Types

struct MCPToolInfo: Identifiable, Sendable {
    let name: String
    let description: String
    let inputSchema: ParameterSchema
    let title: String?

    var id: String { name }

    var displayName: String {
        title?.trimmedNonEmpty ?? name
    }

    /// Description shown to the model. Prefer the human title when it adds information.
    var modelFacingDescription: String {
        if let title = title?.trimmedNonEmpty, title != name {
            if description.isEmpty { return title }
            return "\(title). \(description)"
        }
        return description
    }

    init(name: String, description: String, inputSchema: ParameterSchema, title: String? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.title = title
    }
}

struct MCPToolCallResult: Sendable {
    let text: String
    let isError: Bool
    let rawOutputPath: String?

    init(text: String, isError: Bool, rawOutputPath: String? = nil) {
        self.text = text
        self.isError = isError
        self.rawOutputPath = rawOutputPath
    }
}

// MARK: - Diagnostics

struct DiagnosticsSnapshot: Sendable {
    let stderr: String?
    let launch: LaunchDiagnostics?
    let http: HTTPDiagnostics?
}

struct LaunchDiagnostics: Sendable {
    let executablePath: String
    let args: [String]
    let workingDirectory: String
    let nodeEnvironment: NodeEnvironmentDiagnostics?

    func formatted() -> String {
        var lines: [String] = []
        lines.append("Command:")
        lines.append("\(executablePath) \(CommandLineTokenizer.render(MCPDiagnosticRedaction.redactTokens(args)))")
        lines.append("Working directory:")
        lines.append(workingDirectory)

        if let nodeEnvironment {
            lines.append("Node environment:")
            if let home = nodeEnvironment.home { lines.append("HOME=\(home)") }
            lines.append("NPM_CONFIG_USERCONFIG=\(nodeEnvironment.npmUserConfig)")
            if let cache = nodeEnvironment.npmCache { lines.append("NPM_CONFIG_CACHE=\(cache)") }
            if let prefix = nodeEnvironment.npmPrefix { lines.append("NPM_CONFIG_PREFIX=\(prefix)") }
        }

        return lines.joined(separator: "\n")
    }
}

struct NodeEnvironmentDiagnostics: Sendable {
    let home: String?
    let npmUserConfig: String
    let npmCache: String?
    let npmPrefix: String?
}

struct HTTPDiagnostics: Sendable {
    let endpoint: String
    let headerNames: [String]

    func formatted() -> String {
        var lines: [String] = []
        lines.append("HTTP endpoint:")
        lines.append(endpoint)
        if !headerNames.isEmpty {
            lines.append("HTTP headers:")
            lines.append(headerNames.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Error Types

enum MCPClientError: Error, LocalizedError {
    case notRunning
    case executableNotFound(command: String)
    case invalidCommand
    case environmentSetupFailed(message: String)
    case processLaunchFailed(command: String, underlying: Error)
    case processExited(
        status: Int32,
        reason: MCPProcessExitReason,
        stderr: String?,
        diagnostics: LaunchDiagnostics?
    )
    case requestTimedOut(
        method: String,
        seconds: Double,
        transport: MCPTransportKind,
        stderr: String?,
        diagnostics: LaunchDiagnostics?,
        httpDiagnostics: HTTPDiagnostics?
    )
    case requestFailed(
        method: String,
        transport: MCPTransportKind,
        underlying: Error,
        stderr: String?,
        diagnostics: LaunchDiagnostics?,
        httpDiagnostics: HTTPDiagnostics?
    )

    var errorDescription: String? {
        MCPErrorPresentation.make(from: self).summaryAndHint
    }

    /// Redacted diagnostics for copy/paste. `errorDescription` stays short so
    /// system alerts cannot dump API keys or a multi-page log.
    var detailedDescription: String {
        MCPErrorPresentation.make(from: self).fullText
    }
}
