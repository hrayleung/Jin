import Foundation

extension CodexAppServerFormSupport {
    static func statusPresentation(
        status: CodexAppServerController.Status,
        listenURL: String,
        validationError: String?
    ) -> StatusPresentation {
        StatusPresentation(
            label: statusLabel(for: status),
            tone: statusTone(for: status),
            message: statusMessage(
                for: status,
                listenURL: listenURL,
                validationError: validationError
            )
        )
    }

    static func statusLabel(for status: CodexAppServerController.Status) -> String {
        switch status {
        case .stopped:
            return "Server stopped"
        case .starting:
            return "Server starting"
        case .running:
            return "Server running"
        case .stopping:
            return "Server stopping"
        case .failed:
            return "Server failed"
        }
    }

    static func statusTone(for status: CodexAppServerController.Status) -> StatusTone {
        switch status {
        case .running:
            return .success
        case .starting, .stopping:
            return .warning
        case .stopped:
            return .neutral
        case .failed:
            return .failure
        }
    }

    static func statusMessage(
        for status: CodexAppServerController.Status,
        listenURL: String,
        validationError: String?
    ) -> String {
        if let validationError {
            return validationError
        }

        switch status {
        case .running(let pid, let listenURL):
            return "`codex app-server` is running (pid \(pid)) on \(listenURL)"
        case .starting:
            return "Starting `codex app-server --listen \(listenURL)`..."
        case .stopping:
            return "Stopping `codex app-server`..."
        case .failed(let message):
            return message
        case .stopped:
            return "Ready to launch `codex app-server --listen \(listenURL)`."
        }
    }

    static func buttonState(
        status: CodexAppServerController.Status,
        hasManagedProcesses: Bool,
        validationError: String?
    ) -> ButtonState {
        ButtonState(
            startDisabled: isStartDisabled(status: status, validationError: validationError),
            stopDisabled: isStopDisabled(status: status),
            forceStopDisabled: isForceStopDisabled(
                status: status,
                hasManagedProcesses: hasManagedProcesses
            )
        )
    }

    static func lingeringProcessWarning(
        status: CodexAppServerController.Status,
        managedProcessCount: Int
    ) -> String? {
        guard managedProcessCount > 0, case .stopped = status else { return nil }
        return "Detected \(managedProcessCount) Jin-managed Codex app-server process(es) still running. Use Force Stop to clean them up."
    }

    private static func isStartDisabled(
        status: CodexAppServerController.Status,
        validationError: String?
    ) -> Bool {
        if validationError != nil { return true }

        switch status {
        case .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    private static func isStopDisabled(status: CodexAppServerController.Status) -> Bool {
        switch status {
        case .running, .starting:
            return false
        case .stopped, .stopping, .failed:
            return true
        }
    }

    private static func isForceStopDisabled(
        status: CodexAppServerController.Status,
        hasManagedProcesses: Bool
    ) -> Bool {
        switch status {
        case .stopping, .failed:
            return false
        default:
            return !hasManagedProcesses
        }
    }
}
