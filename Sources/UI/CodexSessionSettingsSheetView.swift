import SwiftUI

struct CodexSessionSettingsSheetView: View {
    @Binding var workingDirectoryDraft: String
    @Binding var workingDirectoryDraftError: String?
    @Binding var sandboxModeDraft: CodexSandboxMode
    @Binding var personalityDraft: CodexPersonality?

    var onChooseDirectory: () -> Void
    var onSelectPreset: (CodexWorkingDirectoryPreset) -> Void
    var onResetWorkingDirectory: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    @State private var presets: [CodexWorkingDirectoryPreset] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    workingDirectorySection
                    sandboxModeSection
                    personalitySection
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Codex Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 380, idealHeight: 440)
        .onAppear {
            presets = CodexWorkingDirectoryPresetsStore.load()
        }
    }

    // MARK: - Working Directory

    private var workingDirectorySection: some View {
        JinSettingsCard(spacing: JinSpacing.small, padding: JinSpacing.medium) {
            Label("Working Directory", systemImage: "folder")
                .font(.subheadline.weight(.semibold))

            Menu {
                if !presets.isEmpty {
                    ForEach(presets) { preset in
                        Button {
                            onSelectPreset(preset)
                        } label: {
                            CodexWorkingDirectoryPresetMenuItemLabel(
                                preset: preset,
                                isSelected: workingDirectoryDraft == preset.path
                            )
                        }
                    }
                    Divider()
                }

                Button {
                    onChooseDirectory()
                } label: {
                    Label("Browse\u{2026}", systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    onResetWorkingDirectory()
                } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                }
                .disabled(workingDirectoryDraft.isEmpty)
            } label: {
                CodexWorkingDirectoryMenuLabel(
                    displayText: workingDirectoryDisplayText,
                    isDefault: workingDirectoryDraft.isEmpty
                )
            }
            .menuStyle(.borderlessButton)

            if let workingDirectoryDraftError, !workingDirectoryDraftError.isEmpty {
                JinSettingsErrorText(text: workingDirectoryDraftError)
            }
        }
    }

    private var workingDirectoryDisplayText: String {
        let trimmed = workingDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "App-server default" : trimmed
    }

    // MARK: - Sandbox Mode

    private var sandboxModeSection: some View {
        JinSettingsCard(spacing: JinSpacing.small, padding: JinSpacing.medium) {
            Label("Sandbox", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: JinSpacing.small) {
                ForEach(CodexSandboxMode.allCases, id: \.self) { mode in
                    Button { sandboxModeDraft = mode } label: {
                        CodexSandboxModeTile(
                            mode: mode,
                            isSelected: sandboxModeDraft == mode
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if sandboxModeDraft == .dangerFullAccess {
                CodexDangerFullAccessWarning()
            }
        }
    }

    // MARK: - Personality

    private var personalitySection: some View {
        JinSettingsCard(spacing: JinSpacing.small, padding: JinSpacing.medium) {
            Label("Personality", systemImage: "face.smiling")
                .font(.subheadline.weight(.semibold))

            Menu {
                Button { personalityDraft = nil } label: {
                    CodexSelectedMenuItemLabel("Model Default", isSelected: personalityDraft == nil)
                }
                Divider()
                ForEach(CodexPersonality.allCases, id: \.self) { personality in
                    Button { personalityDraft = personality } label: {
                        CodexSelectedMenuItemLabel(
                            personality.displayName,
                            isSelected: personalityDraft == personality
                        )
                    }
                }
            } label: {
                CodexPersonalityMenuLabel(title: personalityDraft?.displayName ?? "Model Default")
            }
            .menuStyle(.borderlessButton)
        }
    }
}
