import SwiftUI

extension AgentModeSettingsView {
    var workingDirectorySection: some View {
        JinSettingsSection(
            "Working Directory",
            detail: "Choose the folder Agent Mode can read, search, and edit."
        ) {
            JinSettingsControlRow("Path") {
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    HStack(spacing: JinSpacing.small) {
                        TextField(
                            "Working Directory",
                            text: $workingDirectoryDraft,
                            prompt: Text("e.g., /Users/you/Projects/my-app")
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: workingDirectoryDraft) { _, newValue in
                            applyWorkingDirectory(newValue)
                        }

                        Button("Browse") {
                            selectDirectory()
                        }
                        .buttonStyle(.bordered)
                        .help("Choose a working directory for Agent Mode.")
                    }

                    Text(workingDirectoryValidation.message)
                        .font(.caption)
                        .foregroundStyle(workingDirectoryValidation.isError ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
