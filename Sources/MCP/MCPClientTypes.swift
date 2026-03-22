import Foundation

// MARK: - Public Types

struct MCPToolInfo: Identifiable, Sendable {
    let name: String
    let description: String
    let inputSchema: ParameterSchema

    var id: String { name }
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
        lines.append("\(executablePath) \(CommandLineTokenizer.render(args))")
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
    case processExited(status: Int32, stderr: String?, diagnostics: LaunchDiagnostics?)
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
        switch self {
        case .notRunning:
            return "MCP server is not running."
        case .executableNotFound(let command):
            return "MCP server executable not found: \(command). If you installed it via Homebrew, make sure /opt/homebrew/bin is in PATH, or set a full path in Command."
        case .invalidCommand:
            return "Invalid MCP server command. Use the Command + Arguments fields (or paste a full command line into Command)."
        case .environmentSetupFailed(let message):
            return "Failed to set up MCP server environment.\n\n\(message)"
        case .processLaunchFailed(let command, let underlying):
            return "Failed to start MCP server (\(command)): \(underlying.localizedDescription)"
        case .processExited(let status, let stderr, let diagnostics):
            var message = "MCP server process exited (status: \(status))."
            if let diagnostics {
                message += "\n\n\(diagnostics.formatted())"
            }
            if let stderr, !stderr.isEmpty {
                message += "\n\nstderr:\n\(stderr)"
            }
            return message
        case .requestTimedOut(let method, let seconds, let transport, let stderr, let diagnostics, let httpDiagnostics):
            var message = "MCP request timed out (\(method), \(transport.rawValue)) after \(Int(seconds))s."

            if let diagnostics {
                message += "\n\n\(diagnostics.formatted())"
            }

            if let httpDiagnostics {
                message += "\n\n\(httpDiagnostics.formatted())"
            }

            if let stderr, !stderr.isEmpty {
                message += "\n\nstderr:\n\(stderr)"
            }

            if method == "initialize" {
                switch transport {
                case .stdio:
                    message += "\n\nTip: If this server works in another client, compare the exact command line + env. Jin runs the command directly (no login shell), so tools installed via nvm/asdf/fnm may require using a wrapper script or running via /bin/zsh -lc."
                    message += "\n\nIf you're using npx and it hangs without output, check your ~/.npmrc (e.g. custom prefix=) and consider setting HOME or NPM_CONFIG_USERCONFIG in the server env vars to isolate npm state."
                case .http:
                    message += "\n\nTip: Verify endpoint URL, auth headers/token, and whether the server expects streamable HTTP with SSE enabled."
                }
            }

            return message
        case .requestFailed(let method, let transport, let underlying, let stderr, let diagnostics, let httpDiagnostics):
            var message = "MCP request failed (\(method), \(transport.rawValue)): \(underlying.localizedDescription)"

            if let diagnostics {
                message += "\n\n\(diagnostics.formatted())"
            }

            if let httpDiagnostics {
                message += "\n\n\(httpDiagnostics.formatted())"
            }

            if let stderr, !stderr.isEmpty {
                message += "\n\nstderr:\n\(stderr)"
            }

            return message
        }
    }
}
