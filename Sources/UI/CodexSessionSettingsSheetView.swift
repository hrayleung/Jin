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
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Working Directory", systemImage: "folder")
                .font(.subheadline.weight(.semibold))

            Menu {
                if !presets.isEmpty {
                    ForEach(presets) { preset in
                        Button {
                            onSelectPreset(preset)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                    Text(preset.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                if workingDirectoryDraft == preset.path {
                                    Image(systemName: "checkmark")
                                }
                            }
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
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: workingDirectoryDraft.isEmpty ? "minus" : "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(workingDirectoryDraft.isEmpty ? .secondary : .accentColor)

                    Text(workingDirectoryDisplayText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(workingDirectoryDraft.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, JinSpacing.small + 2)
                .padding(.vertical, JinSpacing.small)
                .jinSurface(.subtle, cornerRadius: JinRadius.small)
            }
            .menuStyle(.borderlessButton)

            if let workingDirectoryDraftError, !workingDirectoryDraftError.isEmpty {
                Text(workingDirectoryDraftError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var workingDirectoryDisplayText: String {
        let trimmed = workingDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "App-server default" : trimmed
    }

    // MARK: - Sandbox Mode

    private var sandboxModeSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Sandbox", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: JinSpacing.small) {
                ForEach(CodexSandboxMode.allCases, id: \.self) { mode in
                    Button { sandboxModeDraft = mode } label: {
                        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                            HStack(spacing: JinSpacing.xSmall) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(mode.displayName)
                                    .font(.caption.weight(.semibold))
                            }
                            Text(mode.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(JinSpacing.small)
                        .jinSurface(
                            sandboxModeDraft == mode ? .selected : .subtle,
                            cornerRadius: JinRadius.small
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if sandboxModeDraft == .dangerFullAccess {
                Label("Full Access disables sandbox protection.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    // MARK: - Personality

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Personality", systemImage: "face.smiling")
                .font(.subheadline.weight(.semibold))

            Menu {
                Button { personalityDraft = nil } label: {
                    menuItemLabel("Model Default", isSelected: personalityDraft == nil)
                }
                Divider()
                ForEach(CodexPersonality.allCases, id: \.self) { personality in
                    Button { personalityDraft = personality } label: {
                        menuItemLabel(personality.displayName, isSelected: personalityDraft == personality)
                    }
                }
            } label: {
                HStack {
                    Text(personalityDraft?.displayName ?? "Model Default")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, JinSpacing.small + 2)
                .padding(.vertical, JinSpacing.small)
                .jinSurface(.subtle, cornerRadius: JinRadius.small)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: JinSpacing.small) {
            Text(title)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
