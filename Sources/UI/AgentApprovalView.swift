import SwiftUI

struct AgentApprovalView: View {
    let request: AgentApprovalRequest
    let onResolve: (AgentApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(request.title)
                    .font(.headline)

                Text(requestDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, JinSpacing.large)
            .padding(.top, JinSpacing.large)
            .padding(.bottom, JinSpacing.medium)

            Divider()
                .padding(.horizontal, JinSpacing.medium)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    switch request.kind {
                    case .shellCommand(let command, let cwd):
                        shellCommandContent(command: command, cwd: cwd)
                    case .fileWrite(let path, let preview):
                        fileWriteContent(path: path, preview: preview)
                    case .fileEdit(let path, let oldText, let newText):
                        fileEditContent(path: path, oldText: oldText, newText: newText)
                    }
                }
                .padding(JinSpacing.large)
            }

            Divider()
                .padding(.horizontal, JinSpacing.medium)

            // Approval buttons
            approvalButtons
                .padding(.horizontal, JinSpacing.large)
                .padding(.vertical, JinSpacing.medium)
        }
        .background(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        .interactiveDismissDisabled(true)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 200, idealHeight: 360)
    }

    private var requestDescription: String {
        switch request.kind {
        case .shellCommand:
            return "The agent wants to execute a shell command that is not in the allowed command list."
        case .fileWrite:
            return "The agent wants to create or overwrite a file."
        case .fileEdit:
            return "The agent wants to modify an existing file."
        }
    }

    // MARK: - Shell Command

    @ViewBuilder
    private func shellCommandContent(command: String, cwd: String?) -> some View {
        codeBlock(label: "Command", content: command)

        if let cwd, !cwd.isEmpty {
            codeBlock(label: "Working Directory", content: cwd)
        }
    }

    // MARK: - File Write

    @ViewBuilder
    private func fileWriteContent(path: String, preview: String) -> some View {
        codeBlock(label: "File Path", content: path)

        if !preview.isEmpty {
            ToolCallCodeBlockView(
                title: "Content Preview",
                text: preview,
                showsCopyButton: true
            )
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
            )
        }
    }

    // MARK: - File Edit

    @ViewBuilder
    private func fileEditContent(path: String, oldText: String, newText: String) -> some View {
        codeBlock(label: "File Path", content: path)

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
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
        )
    }

    // MARK: - Buttons

    private var approvalButtons: some View {
        HStack(spacing: JinSpacing.small) {
            Button(AgentApprovalChoice.deny.displayName) {
                onResolve(.deny)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(AgentApprovalChoice.cancel.displayName) {
                onResolve(.cancel)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(AgentApprovalChoice.allowForSession.displayName) {
                onResolve(.allowForSession)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(AgentApprovalChoice.allow.displayName) {
                onResolve(.allow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Code Block

    private func codeBlock(label: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, JinSpacing.small)
                .padding(.vertical, JinSpacing.xSmall + 2)
                .background(
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.35), lineWidth: JinStrokeWidth.hairline)
                )
        }
    }
}
