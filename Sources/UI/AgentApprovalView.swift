import SwiftUI

struct AgentApprovalView: View {
    let request: AgentApprovalRequest
    let onResolve: (AgentApprovalChoice) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    headerCard

                    switch request.kind {
                    case .shellCommand(let command, let cwd):
                        shellCommandContent(command: command, cwd: cwd)
                    case .fileWrite(let path, let preview):
                        fileWriteContent(path: path, preview: preview)
                    case .fileEdit(let path, let oldText, let newText):
                        fileEditContent(path: path, oldText: oldText, newText: newText)
                    }

                    approvalButtons
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle(request.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onResolve(.cancel)
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 380, idealHeight: 480)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text(requestDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
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

    @ViewBuilder
    private func shellCommandContent(command: String, cwd: String?) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            agentCodeCard(title: "Command", content: command)

            if let cwd, !cwd.isEmpty {
                agentCodeCard(title: "Working Directory", content: cwd)
            }
        }
    }

    @ViewBuilder
    private func fileWriteContent(path: String, preview: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            agentCodeCard(title: "File Path", content: path)

            if !preview.isEmpty {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Content Preview")
                        .font(.headline)
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)
            }
        }
    }

    @ViewBuilder
    private func fileEditContent(path: String, oldText: String, newText: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            agentCodeCard(title: "File Path", content: path)

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Changes")
                    .font(.headline)

                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Remove:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .systemRed))
                    ScrollView {
                        Text(oldText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)

                    Text("Replace with:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    ScrollView {
                        Text(newText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                }
            }
            .padding(JinSpacing.large)
            .jinSurface(.raised, cornerRadius: JinRadius.large)
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: JinSpacing.medium) {
            Button(AgentApprovalChoice.deny.displayName) {
                onResolve(.deny)
            }
            .buttonStyle(.bordered)

            Button(AgentApprovalChoice.cancel.displayName, role: .destructive) {
                onResolve(.cancel)
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 0)

            Button(AgentApprovalChoice.allowForSession.displayName) {
                onResolve(.allowForSession)
            }
            .buttonStyle(.bordered)

            Button(AgentApprovalChoice.allow.displayName) {
                onResolve(.allow)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func agentCodeCard(title: String, content: String) -> some View {
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
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }
}
