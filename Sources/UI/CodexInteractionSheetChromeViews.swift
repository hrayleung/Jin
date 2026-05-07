import SwiftUI

struct CodexInteractionSectionCardView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(JinSpacing.large)
            .jinSurface(.raised, cornerRadius: JinRadius.large)
    }
}

struct CodexInteractionHeaderCardView: View {
    let subtitle: String?
    let description: String
    let threadID: String?
    let turnID: String?

    var body: some View {
        CodexInteractionSectionCardView {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .jinInfoCallout()
                } else {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: JinSpacing.small) {
                    if let threadID, !threadID.isEmpty {
                        CodexInteractionMetaPillView(title: "Thread", value: threadID)
                    }
                    if let turnID, !turnID.isEmpty {
                        CodexInteractionMetaPillView(title: "Turn", value: turnID)
                    }
                }
            }
        }
    }
}

struct CodexCommandApprovalContentView: View {
    let approval: CodexCommandApprovalRequest
    let onResolve: (CodexApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let command = approval.command, !command.isEmpty {
                CodexInteractionCodeCardView(title: "Command", content: command)
            }

            if let cwd = approval.cwd, !cwd.isEmpty {
                CodexInteractionCodeCardView(title: "Working Directory", content: cwd)
            }

            if !approval.actionSummaries.isEmpty {
                CodexCommandActionSummaryCardView(actions: approval.actionSummaries)
            }

            CodexInteractionApprovalButtonRow(onResolve: onResolve)
        }
    }
}

struct CodexFileChangeApprovalContentView: View {
    let approval: CodexFileChangeApprovalRequest
    let onResolve: (CodexApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let grantRoot = approval.grantRoot, !grantRoot.isEmpty {
                CodexInteractionCodeCardView(title: "Requested Write Root", content: grantRoot)
            }

            CodexFileChangeSummaryCardView(fileChanges: approval.fileChanges)

            CodexInteractionApprovalButtonRow(onResolve: onResolve)
        }
    }
}

struct CodexInteractionApprovalButtonRow: View {
    let onResolve: (CodexApprovalChoice) -> Void

    var body: some View {
        HStack(spacing: JinSpacing.medium) {
            Button(CodexApprovalChoice.decline.displayName) {
                onResolve(.decline)
            }
            .buttonStyle(.bordered)

            Button(CodexApprovalChoice.cancel.displayName, role: .destructive) {
                onResolve(.cancel)
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 0)

            Button(CodexApprovalChoice.acceptForSession.displayName) {
                onResolve(.acceptForSession)
            }
            .buttonStyle(.bordered)

            Button(CodexApprovalChoice.accept.displayName) {
                onResolve(.accept)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct CodexInteractionMetaPillView: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.vertical, 4)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }
}

private struct CodexInteractionCodeCardView: View {
    let title: String
    let content: String

    var body: some View {
        CodexInteractionSectionCardView {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text(title)
                    .font(.headline)
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
            }
        }
    }
}

private struct CodexCommandActionSummaryCardView: View {
    let actions: [CodexCommandActionSummary]

    var body: some View {
        CodexInteractionSectionCardView {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Detected Actions")
                    .font(.headline)

                ForEach(actions) { action in
                    CodexCommandActionSummaryRowView(action: action)
                }
            }
        }
    }
}

private struct CodexCommandActionSummaryRowView: View {
    let action: CodexCommandActionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.title)
                .font(.subheadline.weight(.semibold))

            if let subtitle = action.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(JinSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }
}

private struct CodexFileChangeSummaryCardView: View {
    let fileChanges: [CodexFileChangeSummary]

    var body: some View {
        CodexInteractionSectionCardView {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Changed Files")
                    .font(.headline)

                if fileChanges.isEmpty {
                    Text("Codex did not provide a file list, but it is asking for write approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fileChanges) { change in
                        CodexFileChangeSummaryRowView(change: change)
                    }
                }
            }
        }
    }
}

private struct CodexFileChangeSummaryRowView: View {
    let change: CodexFileChangeSummary

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            Text(change.changeType.uppercased())
                .font(.caption2.weight(.bold))
                .padding(.horizontal, JinSpacing.xSmall)
                .padding(.vertical, 3)
                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)

            Text(change.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(JinSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }
}
