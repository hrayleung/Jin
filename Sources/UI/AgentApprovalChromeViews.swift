import SwiftUI

struct AgentApprovalHeaderView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.top, JinSpacing.large)
        .padding(.bottom, JinSpacing.medium)
    }
}

struct AgentApprovalRequestContentView: View {
    let kind: AgentApprovalKind

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            switch kind {
            case .shellCommand(let command, let cwd):
                shellCommandContent(command: command, cwd: cwd)
            case .fileWrite(let path, let preview):
                fileWriteContent(path: path, preview: preview)
            case .fileEdit(let path, let oldText, let newText):
                fileEditContent(path: path, oldText: oldText, newText: newText)
            }
        }
    }

    @ViewBuilder
    private func shellCommandContent(command: String, cwd: String?) -> some View {
        AgentApprovalInlineCodeBlockView(label: "Command", content: command)

        if let cwd, !cwd.isEmpty {
            AgentApprovalInlineCodeBlockView(label: "Working Directory", content: cwd)
        }
    }

    @ViewBuilder
    private func fileWriteContent(path: String, preview: String) -> some View {
        AgentApprovalInlineCodeBlockView(label: "File Path", content: path)

        if !preview.isEmpty {
            AgentApprovalBorderedBlockGroup {
                ToolCallCodeBlockView(
                    title: "Content Preview",
                    text: preview,
                    showsCopyButton: true
                )
            }
        }
    }

    private func fileEditContent(path: String, oldText: String, newText: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            AgentApprovalInlineCodeBlockView(label: "File Path", content: path)

            AgentApprovalBorderedBlockGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ToolCallCodeBlockView(
                        title: "Remove",
                        text: oldText,
                        showsCopyButton: false
                    )

                    ToolCallCodeBlockView(
                        title: "Replace with",
                        text: newText,
                        showsCopyButton: false
                    )
                }
            }
        }
    }
}

struct AgentApprovalButtonRow: View {
    let onResolve: (AgentApprovalChoice) -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            denyButton
            cancelButton
            Spacer(minLength: 0)
            allowForSessionButton
            allowButton
        }
    }

    private var denyButton: some View {
        Button(AgentApprovalChoice.deny.displayName) {
            onResolve(.deny)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var cancelButton: some View {
        Button(AgentApprovalChoice.cancel.displayName) {
            onResolve(.cancel)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }

    private var allowForSessionButton: some View {
        Button(AgentApprovalChoice.allowForSession.displayName) {
            onResolve(.allowForSession)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var allowButton: some View {
        Button(AgentApprovalChoice.allow.displayName) {
            onResolve(.allow)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}

private struct AgentApprovalInlineCodeBlockView: View {
    let label: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            labelText
            contentText
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var contentText: some View {
        Text(content)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, JinSpacing.xSmall + 2)
            .background(codeBlockBackground)
            .overlay(codeBlockBorder)
    }

    private var codeBlockBackground: some View {
        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
            .fill(JinSemanticColor.subtleSurface)
    }

    private var codeBlockBorder: some View {
        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
            .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
    }
}

private struct AgentApprovalBorderedBlockGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
            )
    }
}
