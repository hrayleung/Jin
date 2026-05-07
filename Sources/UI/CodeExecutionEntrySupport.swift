import Foundation

enum CodeExecutionEntrySupport {
    static func visualStatus(for status: CodeExecutionStatus) -> CodeExecVisualStatus {
        switch status {
        case .inProgress, .writingCode, .interpreting:
            return .running
        case .completed:
            return .success
        case .failed, .incomplete:
            return .error
        case .unknown:
            return .neutral
        }
    }

    static func statusLabel(for status: CodeExecutionStatus) -> String {
        switch status {
        case .inProgress:
            return "Starting..."
        case .writingCode:
            return "Writing..."
        case .interpreting:
            return "Running..."
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .incomplete:
            return "Incomplete"
        case .unknown(let rawValue):
            return rawValue.trimmedNonEmpty ?? "Unknown"
        }
    }

    static func statusPlaceholderText(for status: CodeExecutionStatus) -> String {
        switch status {
        case .writingCode:
            return "Writing code..."
        case .interpreting:
            return "Running code..."
        case .inProgress:
            return "Starting..."
        case .completed, .failed, .incomplete, .unknown:
            return ""
        }
    }

    static func hasDisplayableContent(_ activity: CodeExecutionActivity) -> Bool {
        hasText(activity.code)
            || hasText(activity.stdout)
            || hasText(activity.stderr)
            || hasItems(activity.outputImages)
            || hasItems(activity.outputFiles)
            || hasText(activity.containerID)
    }

    static func shouldShowReturnCode(for status: CodeExecutionStatus) -> Bool {
        isTerminalStatusWithReturnCode(status)
    }

    static func codeLanguage(for activity: CodeExecutionActivity) -> CodeExecCodeLanguage? {
        guard let code = activity.code, !code.isEmpty else { return nil }
        return CodeExecCodeLanguage.infer(from: code)
    }

    static func codeBadgeText(for language: CodeExecCodeLanguage?) -> String? {
        guard let language, language != .generic else { return nil }
        return language.badgeLabel
    }

    static func imageOutputSummary(count: Int) -> String {
        count == 1 ? "Generated 1 image output" : "Generated \(count) image outputs"
    }

    static func fileOutputSummary(count: Int) -> String {
        count == 1 ? "Generated 1 file output" : "Generated \(count) file outputs"
    }

    private static func hasText(_ value: String?) -> Bool {
        !(value?.isEmpty ?? true)
    }

    private static func hasItems<Value>(_ values: [Value]?) -> Bool {
        !(values?.isEmpty ?? true)
    }

    private static func isTerminalStatusWithReturnCode(_ status: CodeExecutionStatus) -> Bool {
        status == .completed || status == .failed || status == .incomplete
    }
}
