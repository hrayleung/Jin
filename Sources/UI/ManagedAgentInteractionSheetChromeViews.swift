import SwiftUI

struct ManagedAgentInteractionSectionCardView<Content: View>: View {
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

struct ManagedAgentInteractionHeaderCardView: View {
    let subtitle: String?
    let description: String
    let threadID: String?
    let turnID: String?

    var body: some View {
        ManagedAgentInteractionSectionCardView {
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
                        ManagedAgentInteractionMetaPillView(title: "Thread", value: threadID)
                    }
                    if let turnID, !turnID.isEmpty {
                        ManagedAgentInteractionMetaPillView(title: "Turn", value: turnID)
                    }
                }
            }
        }
    }
}

struct ManagedAgentCommandApprovalContentView: View {
    let approval: ManagedAgentCommandApprovalRequest
    let onResolve: (ManagedAgentApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let command = approval.command, !command.isEmpty {
                ManagedAgentInteractionCodeCardView(title: "Command", content: command)
            }

            if let cwd = approval.cwd, !cwd.isEmpty {
                ManagedAgentInteractionCodeCardView(title: "Working Directory", content: cwd)
            }

            if !approval.actionSummaries.isEmpty {
                ManagedAgentCommandActionSummaryCardView(actions: approval.actionSummaries)
            }

            ManagedAgentInteractionApprovalButtonRow(onResolve: onResolve)
        }
    }
}

struct ManagedAgentFileChangeApprovalContentView: View {
    let approval: ManagedAgentFileChangeApprovalRequest
    let onResolve: (ManagedAgentApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let grantRoot = approval.grantRoot, !grantRoot.isEmpty {
                ManagedAgentInteractionCodeCardView(title: "Requested Write Root", content: grantRoot)
            }

            ManagedAgentFileChangeSummaryCardView(fileChanges: approval.fileChanges)

            ManagedAgentInteractionApprovalButtonRow(onResolve: onResolve)
        }
    }
}

struct ManagedAgentInteractionApprovalButtonRow: View {
    let onResolve: (ManagedAgentApprovalChoice) -> Void

    var body: some View {
        HStack(spacing: JinSpacing.medium) {
            Button(ManagedAgentApprovalChoice.decline.displayName) {
                onResolve(.decline)
            }
            .buttonStyle(.bordered)

            Button(ManagedAgentApprovalChoice.cancel.displayName, role: .destructive) {
                onResolve(.cancel)
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 0)

            Button(ManagedAgentApprovalChoice.acceptForSession.displayName) {
                onResolve(.acceptForSession)
            }
            .buttonStyle(.bordered)

            Button(ManagedAgentApprovalChoice.accept.displayName) {
                onResolve(.accept)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct ManagedAgentInteractionMetaPillView: View {
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

private struct ManagedAgentInteractionCodeCardView: View {
    let title: String
    let content: String

    var body: some View {
        ManagedAgentInteractionSectionCardView {
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

private struct ManagedAgentCommandActionSummaryCardView: View {
    let actions: [ManagedAgentCommandActionSummary]

    var body: some View {
        ManagedAgentInteractionSectionCardView {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Detected Actions")
                    .font(.headline)

                ForEach(actions) { action in
                    ManagedAgentCommandActionSummaryRowView(action: action)
                }
            }
        }
    }
}

private struct ManagedAgentCommandActionSummaryRowView: View {
    let action: ManagedAgentCommandActionSummary

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

private struct ManagedAgentFileChangeSummaryCardView: View {
    let fileChanges: [ManagedAgentFileChangeSummary]

    var body: some View {
        ManagedAgentInteractionSectionCardView {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Changed Files")
                    .font(.headline)

                if fileChanges.isEmpty {
                    Text("The agent did not provide a file list, but is asking for write approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fileChanges) { change in
                        ManagedAgentFileChangeSummaryRowView(change: change)
                    }
                }
            }
        }
    }
}

private struct ManagedAgentFileChangeSummaryRowView: View {
    let change: ManagedAgentFileChangeSummary

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
