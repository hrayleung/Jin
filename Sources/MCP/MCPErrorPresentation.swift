import Foundation

enum MCPProcessExitReason: String, Sendable, Equatable {
    case exited
    case uncaughtSignal

    init(_ reason: Process.TerminationReason) {
        switch reason {
        case .uncaughtSignal:
            self = .uncaughtSignal
        case .exit:
            self = .exited
        @unknown default:
            self = .exited
        }
    }
}

struct MCPErrorPresentation: Sendable, Equatable {
    var title: String
    var summary: String
    var hint: String?
    var details: String?

    var summaryAndHint: String {
        if let hint, !hint.isEmpty {
            return "\(summary)\n\n\(hint)"
        }
        return summary
    }

    var fullText: String {
        var parts = [summaryAndHint]
        if let details, !details.isEmpty {
            parts.append(details)
        }
        return parts.joined(separator: "\n\n")
    }

    static func make(from error: Error) -> MCPErrorPresentation {
        if let clientError = error as? MCPClientError {
            return make(from: clientError)
        }
        if let hubError = error as? MCPHubError {
            return MCPErrorPresentation(
                title: "Couldn't complete MCP action",
                summary: hubError.localizedDescription,
                hint: nil,
                details: nil
            )
        }
        return MCPErrorPresentation(
            title: "Couldn't complete MCP action",
            summary: error.localizedDescription,
            hint: nil,
            details: nil
        )
    }

    static func make(from error: MCPClientError) -> MCPErrorPresentation {
        switch error {
        case .notRunning:
            return MCPErrorPresentation(
                title: "MCP server is not running",
                summary: "The MCP server is not running.",
                hint: "Open Settings → MCP and use Check connection, or send again to restart it.",
                details: nil
            )
        case .executableNotFound(let command):
            return MCPErrorPresentation(
                title: "MCP server not found",
                summary: "Jin couldn't find the MCP server executable \(command).",
                hint: "If you installed it with Homebrew, make sure /opt/homebrew/bin is on PATH, or put the full path in Command.",
                details: nil
            )
        case .invalidCommand:
            return MCPErrorPresentation(
                title: "Invalid MCP command",
                summary: "The MCP server command is empty or could not be parsed.",
                hint: "Use the Command and Arguments fields, or paste a full command line into Command.",
                details: nil
            )
        case .environmentSetupFailed(let message):
            return MCPErrorPresentation(
                title: "Couldn't set up MCP environment",
                summary: "Jin couldn't prepare the isolated environment for this MCP server.",
                hint: nil,
                details: MCPDiagnosticRedaction.redact(message)
            )
        case .processLaunchFailed(let command, let underlying):
            return MCPErrorPresentation(
                title: "Couldn't start MCP server",
                summary: "Jin couldn't start \(command): \(underlying.localizedDescription)",
                hint: nil,
                details: nil
            )
        case .processExited(let status, let reason, let stderr, let diagnostics):
            return processExitedPresentation(
                status: status,
                reason: reason,
                stderr: stderr,
                diagnostics: diagnostics
            )
        case .requestTimedOut(let method, let seconds, let transport, let stderr, let diagnostics, let httpDiagnostics):
            return requestPresentation(
                title: "MCP request timed out",
                summary: "The MCP \(method) request timed out after \(Int(seconds))s (\(transport.rawValue)).",
                method: method,
                transport: transport,
                stderr: stderr,
                diagnostics: diagnostics,
                httpDiagnostics: httpDiagnostics,
                underlying: nil
            )
        case .requestFailed(let method, let transport, let underlying, let stderr, let diagnostics, let httpDiagnostics):
            return requestPresentation(
                title: "MCP request failed",
                summary: "The MCP \(method) request failed (\(transport.rawValue)): \(underlying.localizedDescription)",
                method: method,
                transport: transport,
                stderr: stderr,
                diagnostics: diagnostics,
                httpDiagnostics: httpDiagnostics,
                underlying: underlying
            )
        }
    }

    static func processExitSummary(status: Int32, reason: MCPProcessExitReason) -> String {
        switch reason {
        case .exited:
            if status == 0 {
                return "The MCP server process exited before Jin finished talking to it."
            }
            return "The MCP server process exited (status \(status)) before Jin finished talking to it."
        case .uncaughtSignal:
            if let name = unixSignalName(status) {
                return "The MCP server process was stopped (\(name)) before Jin finished talking to it."
            }
            return "The MCP server process was stopped (signal \(status)) before Jin finished talking to it."
        }
    }

    private static func processExitedPresentation(
        status: Int32,
        reason: MCPProcessExitReason,
        stderr: String?,
        diagnostics: LaunchDiagnostics?
    ) -> MCPErrorPresentation {
        let details = joinedDetails(
            diagnostics: diagnostics,
            httpDiagnostics: nil,
            stderr: stderr
        )
        return MCPErrorPresentation(
            title: "MCP server stopped",
            summary: processExitSummary(status: status, reason: reason),
            hint: hint(
                method: "initialize",
                transport: .stdio,
                stderr: stderr,
                diagnostics: diagnostics,
                processStatus: status,
                processReason: reason
            ),
            details: details
        )
    }

    private static func requestPresentation(
        title: String,
        summary: String,
        method: String,
        transport: MCPTransportKind,
        stderr: String?,
        diagnostics: LaunchDiagnostics?,
        httpDiagnostics: HTTPDiagnostics?,
        underlying: Error?
    ) -> MCPErrorPresentation {
        MCPErrorPresentation(
            title: title,
            summary: summary,
            hint: hint(
                method: method,
                transport: transport,
                stderr: stderr,
                diagnostics: diagnostics,
                processStatus: nil,
                processReason: nil
            ),
            details: joinedDetails(
                diagnostics: diagnostics,
                httpDiagnostics: httpDiagnostics,
                stderr: stderr,
                underlying: underlying
            )
        )
    }

    private static func joinedDetails(
        diagnostics: LaunchDiagnostics?,
        httpDiagnostics: HTTPDiagnostics?,
        stderr: String?,
        underlying: Error? = nil
    ) -> String? {
        var sections: [String] = []

        if let diagnostics {
            sections.append(diagnostics.formatted())
        }
        if let httpDiagnostics {
            sections.append(httpDiagnostics.formatted())
        }
        if let underlying, !(underlying is MCPClientError) {
            let description = MCPDiagnosticRedaction.redact(underlying.localizedDescription)
            if !description.isEmpty {
                sections.append("Underlying error:\n\(description)")
            }
        }
        if let stderr, !stderr.isEmpty {
            sections.append("stderr:\n\(MCPDiagnosticRedaction.redact(stderr))")
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private static func hint(
        method: String,
        transport: MCPTransportKind,
        stderr: String?,
        diagnostics: LaunchDiagnostics?,
        processStatus: Int32?,
        processReason: MCPProcessExitReason?
    ) -> String? {
        let haystack = [
            stderr ?? "",
            diagnostics?.formatted() ?? ""
        ].joined(separator: "\n")

        var hints: [String] = []

        if looksLikeNPMPrefixConflict(haystack) {
            hints.append("npm treated your ~/.npmrc as a project config because the server started in a folder under your home directory. Jin now launches Node MCP servers from a temporary folder and no longer exports NPM_CONFIG_PREFIX.")
        }

        if looksLikeMCPRemoteProxy(haystack) {
            hints.append("This command is only a stdio proxy for a remote MCP URL. In Jin, switch the server to Remote HTTP and paste the same URL — no Node or npx required.")
        }

        if processReason == .uncaughtSignal, processStatus == 15 {
            hints.append("Status 15 is SIGTERM. Jin used to report this after it stopped a failed handshake, which hid the real initialize error. If you still see it, the process was killed before the handshake finished.")
        }

        if hints.isEmpty, method == "initialize" {
            switch transport {
            case .stdio:
                hints.append("Jin runs the command directly (no login shell). Tools installed with nvm, asdf, or fnm may need a full path or /bin/zsh -lc. If npx hangs, check ~/.npmrc.")
            case .http:
                hints.append("Check the endpoint URL and sign-in method. Hosted servers usually want Sign in with browser, or a Bearer token / API header.")
            }
        }

        guard !hints.isEmpty else { return nil }
        return hints.joined(separator: "\n\n")
    }

    static func looksLikeNPMPrefixConflict(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("prefix cannot be changed from project config")
    }

    static func looksLikeMCPRemoteProxy(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("mcp-remote")
    }

    static func unixSignalName(_ status: Int32) -> String? {
        switch status {
        case 1: return "SIGHUP"
        case 2: return "SIGINT"
        case 9: return "SIGKILL"
        case 13: return "SIGPIPE"
        case 15: return "SIGTERM"
        default: return nil
        }
    }
}
