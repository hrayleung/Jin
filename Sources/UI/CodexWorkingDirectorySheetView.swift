import SwiftUI

struct CodexWorkingDirectorySheetView: View {
    @Binding var draft: String
    @Binding var draftError: String?

    var presets: [CodexWorkingDirectoryPreset]
    var onChooseDirectory: () -> Void
    var onSelectPreset: (CodexWorkingDirectoryPreset) -> Void
    var onResetToDefault: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                if !presets.isEmpty {
                    VStack(alignment: .leading, spacing: JinSpacing.small) {
                        Text("Saved Locations")
                            .font(.headline)

                        LazyVStack(alignment: .leading, spacing: JinSpacing.small) {
                            ForEach(presets) { preset in
                                Button {
                                    onSelectPreset(preset)
                                } label: {
                                    HStack(alignment: .top, spacing: JinSpacing.small) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(preset.path)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 0)

                                        if draft == preset.path {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(JinSpacing.small)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .jinSurface(draft == preset.path ? .subtleStrong : .subtle, cornerRadius: JinRadius.small)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Manage this list in Settings → Providers → Codex App Server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(JinSpacing.large)
                    .jinSurface(.raised, cornerRadius: JinRadius.large)
                }

                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Working Directory")
                        .font(.headline)

                    TextField("e.g. ~/projects/my-repo", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Leave empty to use the app-server process default directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)

                HStack(spacing: JinSpacing.medium) {
                    Button("Choose Folder…") {
                        onChooseDirectory()
                    }
                    .buttonStyle(.bordered)

                    Button("Use App-Server Default") {
                        onResetToDefault()
                    }
                    .buttonStyle(.borderless)
                }

                if let draftError, !draftError.isEmpty {
                    Text(draftError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(JinSpacing.small)
                        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                } else {
                    Text("Tip: set this to your project root so Codex tools run in the right repository.")
                        .jinInfoCallout()
                }

                Spacer(minLength: 0)
            }
            .padding(JinSpacing.large)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Codex")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 420)
    }
}
