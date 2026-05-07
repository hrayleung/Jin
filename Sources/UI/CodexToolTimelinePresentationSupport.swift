import Foundation

extension CodexToolTimelineSupport {
    static func collapsedTitle(for entries: [Entry]) -> String {
        let counts = counts(for: entries)
        let toolLabel = entries.count == 1
            ? oneLine(entries[0].activity.toolName, maxLength: 60)
            : "\(entries.count) tools"

        if counts.running > 0, entries.count > 1 {
            return "Codex: \(counts.running) running"
        }
        return "Codex: \(toolLabel)"
    }

    static func compactStatus(for entries: [Entry]) -> CompactStatus? {
        let counts = counts(for: entries)
        if counts.running > 0 { return nil }

        if counts.failed > 0 {
            if counts.succeeded > 0 {
                return CompactStatus(
                    text: "\(summaryCountText(counts.succeeded, singular: "ok", plural: "ok")) / \(summaryCountText(counts.failed, singular: "failed", plural: "failed"))",
                    icon: "xmark.circle.fill",
                    tone: .failure
                )
            }
            return CompactStatus(
                text: summaryCountText(counts.failed, singular: "failed", plural: "failed"),
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

    static func statusSummaryText(for entries: [Entry]) -> String? {
        let counts = counts(for: entries)
        var parts: [String] = []

        if counts.succeeded > 0 {
            parts.append(summaryCountText(counts.succeeded, singular: "success", plural: "successes"))
        }
        if counts.failed > 0 {
            parts.append(summaryCountText(counts.failed, singular: "failed", plural: "failed"))
        }
        if counts.running > 0 {
            parts.append(summaryCountText(counts.running, singular: "running", plural: "running"))
        }

        return parts.isEmpty ? nil : "(" + parts.joined(separator: " / ") + ")"
    }

    static func statusLabel(for status: ToolCallExecutionStatus) -> String {
        ToolTimelineTextSupport.statusLabel(for: status)
    }

    static func toolIconName(for name: String) -> String {
        let lower = name.lowercased()
        let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if lower.contains("shell") || lower.contains("command") || lower.contains("exec")
            || lower.contains("bash") || lower.contains("terminal")
            || lower.hasPrefix("sh") || lower.hasPrefix("zsh")
            || lower.hasPrefix("python") || lower.hasPrefix("node")
            || lower.hasPrefix("npm") || lower.hasPrefix("cargo")
            || lower.hasPrefix("swift") || lower.hasPrefix("make")
            || lower.hasPrefix("git") || lower.hasPrefix("cd ")
            || lower.hasPrefix("echo") || lower.hasPrefix("curl") {
            return "terminal"
        }
        if lower.contains("write") || lower.contains("edit") || lower.contains("patch")
            || lower.contains("create_file") || lower.contains("apply")
            || lower.hasPrefix("file change") || lower.contains("file_change")
            || lower.contains(": ")
        {
            return "pencil.line"
        }
        if lower.contains("read") || lower.contains("cat") || lower.contains("view")
            || lower.contains("get_file") || lower.contains("image view") {
            return "doc.text"
        }
        if lower.contains("search") || lower.contains("grep") || lower.contains("find")
            || lower.contains("ripgrep") || tokens.contains(where: { $0 == "rg" }) {
            return "magnifyingglass"
        }
        if lower.hasPrefix("ls") || lower.hasPrefix("dir")
            || lower.contains("list") || lower.contains("tree") {
            return "folder"
        }
        if lower.contains("mcp") || lower.contains("/") {
            return "puzzlepiece"
        }
        if lower.contains("collab") || lower.contains("spawn") || lower.contains("agent") {
            return "person.2"
        }
        return "gearshape"
    }

    static func summaryCountText(_ count: Int, singular: String, plural: String) -> String {
        ToolTimelineTextSupport.summaryCountText(count, singular: singular, plural: plural)
    }

    static func oneLine(_ string: String, maxLength: Int) -> String {
        ToolTimelineTextSupport.oneLine(string, maxLength: maxLength)
    }
}
