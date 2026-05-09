import SwiftUI

extension AgentModeSettingsView {
    var toolTogglesSection: some View {
        JinSettingsSection("Enabled Tools") {
            AgentModeToolToggle("Shell Execute", systemImage: "terminal", isOn: $enableShell)
            AgentModeToolToggle("File Read", systemImage: "doc.text", isOn: $enableFileRead)
            AgentModeToolToggle("File Write", systemImage: "square.and.pencil", isOn: $enableFileWrite)
            AgentModeToolToggle("File Edit", systemImage: "pencil.line", isOn: $enableFileEdit)
            AgentModeToolToggle("Glob Search", systemImage: "doc.text.magnifyingglass", isOn: $enableGlob)
            AgentModeToolToggle("Grep Search", systemImage: "magnifyingglass", isOn: $enableGrep)
        }
    }

    var safetySection: some View {
        JinSettingsSection("Safety") {
            JinSettingsToggleRow(
                "Auto-approve file reads",
                supportingText: "Skips approval prompts for read-only file access.",
                isOn: $autoApproveFileReads
            )

            JinSettingsControlRow(
                "Command Timeout",
                supportingText: "Maximum shell runtime before Jin terminates the command."
            ) {
                HStack(spacing: JinSpacing.small) {
                    Slider(
                        value: Binding(
                            get: { Double(commandTimeoutSeconds) },
                            set: { commandTimeoutSeconds = Int($0) }
                        ),
                        in: 30...600,
                        step: 30
                    )
                    Text("\(commandTimeoutSeconds)s")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 45, alignment: .trailing)
                }
            }
        }
    }

    var detailsSection: some View {
        JinSettingsSection("Details") {
            JinDetailsDisclosure(title: "How Agent Mode Works") {
                AgentModeDetailsText("Runs shell commands, searches codebases, edits files.")
                AgentModeDetailsText("Shell/grep/glob run through RTK. Reads and edits stay local.")
            }

            JinDetailsDisclosure(title: "Approval Rules") {
                AgentModeDetailsText("Auto-approval matches prefix; RTK rejects commands it can't rewrite.")
                AgentModeDetailsText("Allowed prefixes extend the auto-approval list.")
            }

            JinDetailsDisclosure(title: "RTK") {
                AgentModeDetailsText("Shell commands must be rewriteable by RTK.")
                AgentModeDetailsText("RTK output is logged for later replay.")
            }
        }
    }
}

private struct AgentModeToolToggle: View {
    private let title: String
    private let systemImage: String
    @Binding private var isOn: Bool

    init(_ title: String, systemImage: String, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct AgentModeDetailsText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
