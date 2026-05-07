import Foundation

enum ToolTimelineTextSupport {
    static func statusLabel(for status: ToolCallExecutionStatus) -> String {
        switch status {
        case .running: return "Running"
        case .success: return "Done"
        case .error: return "Failed"
        }
    }

    static func summaryCountText(_ count: Int, singular: String, plural: String) -> String {
        if count <= 1 {
            return singular
        }
        return "\(count) \(plural)"
    }

    static func oneLine(_ string: String, maxLength: Int) -> String {
        let condensed = string
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 3)) + "..."
    }
}
