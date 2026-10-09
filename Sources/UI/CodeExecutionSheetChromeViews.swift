import SwiftUI

struct CodeExecutionBasicsCard: View {
    @Binding var isEnabled: Bool

    var body: some View {
        JinSettingsFeatureToggleCard(
            toggleTitle: "Enable code execution",
            isEnabled: $isEnabled
        )
    }
}

struct CodeExecutionOpenAISettingsCard: View {
    @Binding var useExistingContainer: Bool
    @Binding var existingContainerID: String
    @Binding var memoryLimit: String
    @Binding var fileIDsDraft: String

    var body: some View {
        JinSettingsCard {
            title
            modeRow
            if useExistingContainer {
                existingContainerRow
            } else {
                autoContainerRows
            }
        }
    }

    private var title: some View {
        Text("OpenAI Container")
            .font(.headline)
    }

    private var modeRow: some View {
        JinSettingsControlRow("Mode") {
            JinSettingsSegmentedPicker("Mode", selection: $useExistingContainer) {
                Text("Auto").tag(false)
                Text("Existing").tag(true)
            }
        }
    }

    private var existingContainerRow: some View {
        JinSettingsControlRow("Container ID", supportingText: "Reuses an existing container.") {
            JinSettingsTextField("cntr_...", text: $existingContainerID, usesMonospacedFont: true)
        }
    }

    @ViewBuilder
    private var autoContainerRows: some View {
        memoryLimitRow
        fileIDsRow
    }

    private var memoryLimitRow: some View {
        JinSettingsControlRow("Memory limit") {
            JinSettingsMenuPicker("Memory limit", selection: $memoryLimit) {
                Text("Provider default").tag("")
                Text("1g").tag("1g")
                Text("4g").tag("4g")
                Text("16g").tag("16g")
                Text("64g").tag("64g")
            }
        }
    }

    private var fileIDsRow: some View {
        JinSettingsBlockRow("Extra file IDs", supportingText: "One file ID per line or comma-separated.") {
            JinSettingsTextEditor(text: $fileIDsDraft, minHeight: 84)
        }
    }
}

struct CodeExecutionAnthropicSettingsCard: View {
    @Binding var containerID: String

    var body: some View {
        JinSettingsCard {
            title
            containerIDRow
        }
    }

    private var title: some View {
        Text("Anthropic Container")
            .font(.headline)
    }

    private var containerIDRow: some View {
        JinSettingsControlRow("Container ID", supportingText: "Leave empty to create a new container.") {
            JinSettingsTextField("container_...", text: $containerID, usesMonospacedFont: true)
        }
    }
}

struct CodeExecutionProviderInfoCard: View {
    let title: String
    let message: String

    var body: some View {
        JinSettingsCard {
            header
            messageText
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text(title)
                .font(.headline)
        }
    }

    private var messageText: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CodeExecutionSheetFooter: View {
    let draftError: String?
    let summaryText: String
    let providerDetailText: String

    var body: some View {
        JinSettingsSheetFooter(draftError: draftError, showsDetailsWhenError: false) {
            JinSettingsFooterText(summaryText)
            JinSettingsFooterText(providerDetailText)
        }
    }
}
