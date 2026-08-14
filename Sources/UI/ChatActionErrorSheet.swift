import SwiftUI

struct ChatActionErrorPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let summary: String
    let hint: String?
    let details: String?

    init(
        title: String = "Couldn't complete chat action",
        summary: String,
        hint: String? = nil,
        details: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.hint = hint
        self.details = details
    }

    var copyText: String {
        var parts = [title, summary]
        if let hint, !hint.isEmpty {
            parts.append(hint)
        }
        if let details, !details.isEmpty {
            parts.append(details)
        }
        return parts.joined(separator: "\n\n")
    }

    static func from(message: String) -> ChatActionErrorPresentation {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = trimmed.range(of: "\n\n") else {
            return ChatActionErrorPresentation(summary: trimmed.isEmpty ? "Please try again." : trimmed)
        }

        let summary = String(trimmed[..<split.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let details = String(trimmed[split.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatActionErrorPresentation(
            summary: summary.isEmpty ? "Please try again." : summary,
            details: details.isEmpty ? nil : details
        )
    }

    static func from(error: Error) -> ChatActionErrorPresentation {
        if error is MCPClientError || error is MCPHubError {
            return from(mcp: MCPErrorPresentation.make(from: error))
        }
        return from(message: error.localizedDescription)
    }

    static func from(mcp: MCPErrorPresentation) -> ChatActionErrorPresentation {
        ChatActionErrorPresentation(
            title: mcp.title,
            summary: mcp.summary,
            hint: mcp.hint,
            details: mcp.details
        )
    }

    static func mcpLoadFailures(
        _ failures: [MCPServerToolLoadFailure],
        messageStillSent: Bool
    ) -> ChatActionErrorPresentation {
        guard let only = failures.count == 1 ? failures.first : nil else {
            let names = failures.map(\.serverName).joined(separator: ", ")
            let summary = messageStillSent
                ? "Jin couldn't start \(failures.count) MCP servers (\(names)). Your message was still sent without those tools."
                : "Jin couldn't start \(failures.count) MCP servers (\(names))."
            return ChatActionErrorPresentation(
                title: "Couldn't connect to MCP servers",
                summary: summary,
                hint: failures.compactMap(\.presentation.hint).first,
                details: combinedDetails(failures)
            )
        }

        let summary = messageStillSent
            ? "Jin couldn't start \(only.serverName). Your message was still sent without that server's tools."
            : "Jin couldn't start \(only.serverName)."
        return ChatActionErrorPresentation(
            title: "Couldn't connect to MCP server",
            summary: summary,
            hint: only.presentation.hint,
            details: combinedDetails(failures)
        )
    }

    private static func combinedDetails(_ failures: [MCPServerToolLoadFailure]) -> String? {
        let blocks = failures.compactMap { failure -> String? in
            var lines = ["\(failure.serverName) (\(failure.serverID))"]
            lines.append(failure.presentation.summary)
            if let details = failure.presentation.details, !details.isEmpty {
                lines.append(details)
            }
            return lines.joined(separator: "\n")
        }
        guard !blocks.isEmpty else { return nil }
        return blocks.joined(separator: "\n\n")
    }
}

struct ChatActionErrorSheet: View {
    let presentation: ChatActionErrorPresentation
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    Text(presentation.summary)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let hint = presentation.hint {
                        Text(hint)
                            .jinInfoCallout()
                    }

                    if let details = presentation.details, !details.isEmpty {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            Text("Details")
                                .font(.subheadline.weight(.semibold))
                            Text(details)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(JinSpacing.medium)
                                .jinSurface(.outlined, cornerRadius: JinRadius.medium)
                        }
                    }
                }
                .padding(JinSpacing.large)
            }
            Divider()
            footer
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 720, minHeight: 280, idealHeight: 440)
        .background(JinSemanticColor.detailSurface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: JinSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(.top, 2)

            Text(presentation.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(JinSpacing.large)
    }

    private var footer: some View {
        HStack {
            if presentation.details != nil {
                Button("Copy Details") {
                    PasteboardSupport.writeString(presentation.copyText)
                }
            }
            Spacer()
            Button("Close") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(JinSpacing.large)
    }
}
