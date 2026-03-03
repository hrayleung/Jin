import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CodexWorkingDirectoryPresetsManagerSheetView: View {
    @Binding var presets: [CodexWorkingDirectoryPreset]

    var onCancel: () -> Void
    var onSave: () -> Void

    @State private var showingAddPresetSheet = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                Text("Save a name + path so users can switch cwd quickly from chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presets.isEmpty {
                    Text("No presets yet. Add your common project roots.")
                        .jinInfoCallout()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: JinSpacing.small) {
                            ForEach(presets) { preset in
                                HStack(alignment: .top, spacing: JinSpacing.small) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(preset.path)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    Button(role: .destructive) {
                                        presets.removeAll { $0.id == preset.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(JinSpacing.small)
                                .jinSurface(.outlined, cornerRadius: JinRadius.small)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }

                Spacer(minLength: 0)
            }
            .padding(JinSpacing.large)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("CWD Presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        presets = sortedPresets(presets)
                        onSave()
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAddPresetSheet = true
                    } label: {
                        Label("Add Preset", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPresetSheet) {
            CodexWorkingDirectoryPresetEditorSheetView(
                onCancel: { showingAddPresetSheet = false },
                onSave: { name, path in
                    addPreset(name: name, path: path)
                }
            )
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 420, idealHeight: 460)
    }

    private func sortedPresets(_ input: [CodexWorkingDirectoryPreset]) -> [CodexWorkingDirectoryPreset] {
        input.sorted { lhs, rhs in
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame { return nameCompare == .orderedAscending }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func addPreset(name: String, path: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Name is required." }

        guard let normalizedPath = CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(
            from: path,
            requireExistingDirectory: true
        ) else {
            return "Choose an existing local folder (absolute path or ~/path)."
        }

        let dedupeKey = normalizedPath.lowercased()
        guard !presets.contains(where: { $0.path.lowercased() == dedupeKey }) else {
            return "This folder is already saved."
        }

        presets.append(CodexWorkingDirectoryPreset(name: trimmedName, path: normalizedPath))
        presets = sortedPresets(presets)
        showingAddPresetSheet = false
        return nil
    }
}

private struct CodexWorkingDirectoryPresetEditorSheetView: View {
    @State private var nameDraft = ""
    @State private var pathDraft = ""
    @State private var errorText: String?

    var onCancel: () -> Void
    var onSave: (String, String) -> String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JinSpacing.large) {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Preset Name")
                        .font(.headline)
                    TextField("e.g. Jin App Server", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)

                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Working Directory Path")
                        .font(.headline)
                    HStack(spacing: JinSpacing.small) {
                        TextField("e.g. ~/projects/jin", text: $pathDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button("Choose Folder…") { chooseFolder() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(JinSpacing.small)
                        .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                } else {
                    Text("Both name and path are shown in chat, so keep them clear and short.")
                        .jinInfoCallout()
                }

                Spacer(minLength: 0)
            }
            .padding(JinSpacing.large)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("New CWD Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { savePreset() }
                        .disabled(
                            nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || pathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .onChange(of: nameDraft) { _, _ in
            if errorText != nil { errorText = nil }
        }
        .onChange(of: pathDraft) { _, _ in
            if errorText != nil { errorText = nil }
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 320, idealHeight: 360)
    }

    private func savePreset() {
        if let message = onSave(nameDraft, pathDraft) {
            errorText = message
        }
    }

    private func chooseFolder() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Choose a working directory."

        if let existing = CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(
            from: pathDraft,
            requireExistingDirectory: true
        ) {
            panel.directoryURL = URL(fileURLWithPath: existing, isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        pathDraft = selectedURL.path
        errorText = nil
#endif
    }
}
