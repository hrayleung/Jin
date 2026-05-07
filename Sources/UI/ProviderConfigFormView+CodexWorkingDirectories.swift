import SwiftUI

extension ProviderConfigFormView {
    var codexWorkingDirectoryPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: JinSpacing.small) {
                Label("Working Directory Presets", systemImage: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Manage…") {
                    codexWorkingDirectoryPresetsDraft = codexWorkingDirectoryPresets
                    showingCodexWorkingDirectoryPresetsSheet = true
                }
                .buttonStyle(.borderless)
            }

            if codexWorkingDirectoryPresets.isEmpty {
                Text("No presets configured.")
                    .jinInfoCallout()
            } else {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("\(codexWorkingDirectoryPresets.count) preset(s) available in chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: JinSpacing.xSmall) {
                            ForEach(codexWorkingDirectoryPresets.prefix(4)) { preset in
                                Text(preset.name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, JinSpacing.small)
                                    .padding(.vertical, 4)
                                    .jinSurface(.outlined, cornerRadius: JinRadius.small)
                            }
                            if codexWorkingDirectoryPresets.count > 4 {
                                Text("+\(codexWorkingDirectoryPresets.count - 4) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    func loadCodexWorkingDirectoryPresets() {
        codexWorkingDirectoryPresets = CodexWorkingDirectoryPresetsStore.load()
    }

    func persistCodexWorkingDirectoryPresets() {
        CodexWorkingDirectoryPresetsStore.save(codexWorkingDirectoryPresets)
        codexWorkingDirectoryPresets = CodexWorkingDirectoryPresetsStore.load()
    }
}
