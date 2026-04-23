import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TTSKitTextToSpeechSettingsSection: View {
    @Binding var modelSelection: String
    @Binding var voiceSelection: String
    @Binding var languageSelection: String
    @Binding var styleInstruction: String
    @Binding var playbackModeRaw: String

    @State private var status: TTSKitService.Status = .idle
    @State private var library = TTSKitService.placeholderLibrarySnapshot
    @State private var statusTask: Task<Void, Never>?
    @State private var deletionTarget: TTSKitService.LocalModel?

    private var selectedPreset: TTSKitModelCatalog.Preset? {
        TTSKitModelCatalog.preset(for: modelSelection)
    }

    private var selectedLocalModel: TTSKitService.LocalModel? {
        library.localModel(id: TTSKitModelCatalog.normalizedModelID(modelSelection))
    }

    private var selectedPlaybackMode: TTSKitPlaybackMode {
        TTSKitPlaybackMode.resolved(playbackModeRaw)
    }

    private var selectedVoiceSummary: String? {
        guard !voiceSelection.isEmpty else { return nil }
        return TTSKitModelCatalog.voices.first(where: { $0.id == voiceSelection })?.summary
    }

    private var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    var body: some View {
        Group {
            modelSection
            playbackSection
            optionsSection
            if !library.localModels.isEmpty {
                downloadedModelsSection
            }
            storageSection
        }
        .task {
            normalizeSelectionsIfNeeded()
            await refreshLibrary()
            observeStatus()
        }
        .onDisappear {
            statusTask?.cancel()
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            )
        ) {
            Button("Remove Download", role: .destructive) {
                guard let deletionTarget else { return }
                Task { await deleteModel(deletionTarget) }
            }
            Button("Cancel", role: .cancel) {
                deletionTarget = nil
            }
        } message: {
            Text(deletionDialogMessage)
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        JinSettingsSection("TTSKit (On-Device)") {
            Text("On-device speech synthesis powered by Core ML.")
                .jinInfoCallout()

            Picker("Model", selection: $modelSelection) {
                ForEach(TTSKitModelCatalog.presets) { preset in
                    Text("\(preset.title) \u{00B7} \(preset.approximateSize)")
                        .tag(preset.id)
                }
            }
            .pickerStyle(.menu)

            if let selectedPreset {
                Text(selectedPreset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .downloading(let progress) = status {
                ProgressView(value: progress) {
                    Text("Downloading\u{2026} \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if case .error(let message) = status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if selectedLocalModel == nil {
                Label("Will be downloaded automatically on first use.", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        JinSettingsSection("Playback") {
            Picker("Playback Mode", selection: $playbackModeRaw) {
                ForEach(TTSKitPlaybackMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)

            Text(selectedPlaybackMode.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        JinSettingsSection("Options") {
            Picker("Voice", selection: $voiceSelection) {
                Text("Default (Ryan)")
                    .tag("")
                ForEach(TTSKitModelCatalog.voices) { voice in
                    Text(voice.displayName)
                        .tag(voice.id)
                }
            }
            .pickerStyle(.menu)

            if let selectedVoiceSummary {
                Text(selectedVoiceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Language", selection: $languageSelection) {
                Text("Default (English)")
                    .tag("")
                ForEach(TTSKitModelCatalog.languages) { language in
                    Text(language.displayName)
                        .tag(language.id)
                }
            }
            .pickerStyle(.menu)

            if selectedPreset?.supportsStyleInstruction == true {
                TextField(text: $styleInstruction, prompt: Text("Optional speaking style")) {
                    Text("Style Direction")
                }
                .help("Only Qwen3 TTS 1.7B supports style directions (e.g. calm, excited, documentary narration).")
            } else {
                Text("Style directions are only available on Qwen3 TTS 1.7B.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Downloaded Models

    private var downloadedModelsSection: some View {
        JinSettingsSection("Downloaded Models") {
            ForEach(library.localModels) { localModel in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(TTSKitModelCatalog.preset(for: localModel.id)?.title ?? localModel.id)
                            .font(.subheadline.weight(.medium))

                        Spacer(minLength: 8)

                        if localModel.id == modelSelection {
                            Text("Selected")
                                .jinTagStyle(foreground: Color.accentColor)
                        }
                    }

                    HStack(spacing: 10) {
                        if localModel.id != modelSelection {
                            Button("Use This") {
                                modelSelection = localModel.id
                            }
                        }

                        Button("Reveal in Finder") {
                            revealRepositoryRoot()
                        }

                        Button("Remove", role: .destructive) {
                            deletionTarget = localModel
                        }
                        .disabled(isDownloading)

                        Spacer()
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Storage (progressive disclosure)

    private var storageSection: some View {
        JinSettingsSection(
            "Storage",
            detail: "Manage downloaded models or import them manually.",
            style: .plain
        ) {
            DisclosureGroup("Storage & Manual Import") {
                Text(library.repositoryRootURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        openStorageFolder()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }

                    Button("Refresh") {
                        Task { await refreshLibrary() }
                    }

                    CopyToPasteboardButton(
                        text: library.repositoryRootURL.path,
                        helpText: "Copy folder path",
                        useProminentStyle: false
                    )

                    Spacer()
                }
                .controlSize(.small)

                Text("Each TTSKit model is split across six component directories. Keep the original layout intact if managing files manually.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private var deletionDialogTitle: String {
        guard let deletionTarget else { return "Remove downloaded model?" }
        let title = TTSKitModelCatalog.preset(for: deletionTarget.id)?.title ?? deletionTarget.id
        return "Remove \(title)?"
    }

    private var deletionDialogMessage: String {
        guard let deletionTarget else { return "The model files will be deleted from disk." }
        return "This removes local files for \(deletionTarget.id). You can re-download later."
    }

    // MARK: - Actions

    private func normalizeSelectionsIfNeeded() {
        modelSelection = TTSKitModelCatalog.normalizedModelID(modelSelection)
        playbackModeRaw = selectedPlaybackMode.rawValue

        if !voiceSelection.isEmpty,
           !TTSKitModelCatalog.voices.contains(where: { $0.id == voiceSelection }) {
            voiceSelection = ""
        }

        if !languageSelection.isEmpty,
           !TTSKitModelCatalog.languages.contains(where: { $0.id == languageSelection }) {
            languageSelection = ""
        }
    }

    private func observeStatus() {
        statusTask?.cancel()
        statusTask = Task {
            for await nextStatus in await TTSKitService.shared.statusStream() {
                guard !Task.isCancelled else { break }
                let snapshot = await TTSKitService.shared.librarySnapshot()
                await MainActor.run {
                    status = nextStatus
                    library = snapshot
                }
            }
        }
    }

    private func refreshLibrary() async {
        let service = TTSKitService.shared
        let snapshot = await service.librarySnapshot()
        let currentStatus = await service.status
        await MainActor.run {
            library = snapshot
            status = currentStatus
        }
    }

    private func deleteModel(_ localModel: TTSKitService.LocalModel) async {
        do {
            try await TTSKitService.shared.deleteModel(localModel.id)
        } catch {
            await MainActor.run {
                status = .error(error.localizedDescription)
            }
        }

        await MainActor.run {
            if localModel.id == modelSelection {
                modelSelection = TTSKitModelCatalog.presets.first?.id ?? TTSKitModelCatalog.defaultModelID
            }
            deletionTarget = nil
        }

        await refreshLibrary()
    }

    private func openStorageFolder() {
        try? FileManager.default.createDirectory(at: library.repositoryRootURL, withIntermediateDirectories: true)
        #if os(macOS)
        NSWorkspace.shared.open(library.repositoryRootURL)
        #endif
    }

    private func revealRepositoryRoot() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([library.repositoryRootURL])
        #endif
    }
}
