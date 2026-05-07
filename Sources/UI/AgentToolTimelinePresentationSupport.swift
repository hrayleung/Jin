import Foundation

extension AgentToolTimelineSupport {
    static func displayName(for toolName: String) -> String {
        toolName.replacingOccurrences(of: AgentToolNames.functionNamePrefix, with: "")
    }

    static func collapsedTitle(for activities: [CodexToolActivity]) -> String {
        let counts = counts(for: activities)
        if activities.count == 1 {
            return "Agent · \(displayName(for: activities[0].toolName))"
        }
        if counts.running > 0 {
            return "Agent · \(counts.running) running"
        }
        return "Agent · \(activities.count) tools"
    }

    static func compactStatus(for activities: [CodexToolActivity]) -> CompactStatus? {
        let counts = counts(for: activities)
        if counts.running > 0 { return nil }

        if counts.failed > 0 {
            let label = counts.succeeded > 0
                ? "\(counts.succeeded) ok / \(counts.failed) failed"
                : (counts.failed == 1 ? "Failed" : "\(counts.failed) failed")
            return CompactStatus(
                text: label,
                icon: "xmark.circle.fill",
                tone: .failure
            )
        }

        if counts.succeeded > 0 {
            return CompactStatus(
                text: counts.succeeded == 1 ? "Succeeded" : "All succeeded",
                icon: "checkmark.circle.fill",
                tone: .success
            )
        }

        return nil
    }

    static func toolIconName(for toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("shell") || lower.contains("execute") { return "terminal" }
        if lower.contains("file_read") || lower.contains("read") { return "doc.text" }
        if lower.contains("file_write") || lower.contains("write") { return "square.and.pencil" }
        if lower.contains("file_edit") || lower.contains("edit") { return "pencil.line" }
        if lower.contains("glob") { return "doc.text.magnifyingglass" }
        if lower.contains("grep") { return "magnifyingglass" }
        return "gearshape"
    }

    static func statusLabel(for status: ToolCallExecutionStatus) -> String {
        ToolTimelineTextSupport.statusLabel(for: status)
    }

    static func oneLine(_ string: String, maxLength: Int) -> String {
        ToolTimelineTextSupport.oneLine(string, maxLength: maxLength)
    }
}
