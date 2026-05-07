import SwiftUI
#if os(macOS)
import AppKit
#endif

struct WhisperKitSpeechToTextSettingsSection: View {
    @Binding var modelSelection: String
    @Binding var language: String
    @Binding var translateToEnglish: Bool

    @State private var status: WhisperKitService.Status = .idle
    @State private var library = WhisperKitService.placeholderLibrarySnapshot
    @State private var statusTask: Task<Void, Never>?
    @State private var deletionTarget: WhisperKitService.LocalModel?

    private var selectedPreset: WhisperKitModelCatalog.Preset? {
        WhisperKitModelCatalog.preset(for: modelSelection)
    }

    private var selectedLocalModel: WhisperKitService.LocalModel? {
        library.localModel(matching: modelSelection)
    }

    private var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    var body: some View {
        Group {
            modelSection
            optionsSection
            if !library.localModels.isEmpty {
                downloadedModelsSection
            }
            storageSection
        }
        .task {
            normalizeSelectionIfNeeded()
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
        JinSettingsSection("WhisperKit (On-Device)") {
            Text("On-device speech recognition powered by Core ML.")
                .jinInfoCallout()

            JinSettingsPickerRow("Model", selection: $modelSelection) {
                ForEach(WhisperKitModelCatalog.presets) { preset in
                    Text("\(preset.title) \u{00B7} \(preset.approximateSize)")
                        .tag(preset.id)
                }
            }

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

    // MARK: - Options

    private var optionsSection: some View {
        JinSettingsSection("Options") {
            JinSettingsToggleRow("Translate to English", isOn: $translateToEnglish)
                .help("Translate non-English speech to English instead of transcribing in the original language.")

            JinSettingsTextFieldRow(
                "Language",
                fieldTitle: "Auto-detect",
                text: $language,
                usesMonospacedFont: true
            )
            .help("ISO 639-1 code (e.g. en, zh, ja). Leave empty for auto-detection.")
        }
    }

    // MARK: - Downloaded Models

    private var downloadedModelsSection: some View {
        JinSettingsSection("Downloaded Models") {
            ForEach(library.localModels) { localModel in
                WhisperKitDownloadedModelRow(
                    localModel: localModel,
                    isSelected: isSelected(localModel),
                    isDownloading: isDownloading,
                    onUse: { presetID in
                        modelSelection = presetID
                    },
                    onReveal: {
                        reveal(localModel.folderURL)
                    },
                    onRemove: {
                        deletionTarget = localModel
                    }
                )
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
            OnDeviceModelStorageDisclosure(
                repositoryRootURL: library.repositoryRootURL,
                guidanceText: "Place a valid WhisperKit model folder here and press Refresh to import manually.",
                onOpenFolder: openStorageFolder,
                onRefresh: {
                    Task { await refreshLibrary() }
                }
            )
        }
    }

    // MARK: - Helpers

    private var deletionDialogTitle: String {
        guard let deletionTarget else { return "Remove downloaded model?" }
        return "Remove \(WhisperKitModelCatalog.title(for: deletionTarget.id))?"
    }

    private var deletionDialogMessage: String {
        guard let deletionTarget else { return "The model files will be deleted from disk." }
        return "This removes local files for \(deletionTarget.id). You can re-download later."
    }

    private func isSelected(_ localModel: WhisperKitService.LocalModel) -> Bool {
        if localModel.id == modelSelection { return true }
        guard let preset = selectedPreset else { return false }
        return preset.matchesExactModelID(localModel.id)
    }

    // MARK: - Actions

    private func normalizeSelectionIfNeeded() {
        if let preset = WhisperKitModelCatalog.preset(for: modelSelection) {
            if modelSelection != preset.id {
                modelSelection = preset.id
            }
            return
        }

        if WhisperKitModelCatalog.preset(for: modelSelection) == nil {
            modelSelection = WhisperKitModelCatalog.defaultSelection
        }
    }

    private func observeStatus() {
        statusTask?.cancel()
        statusTask = Task {
            for await nextStatus in await WhisperKitService.shared.statusStream() {
                guard !Task.isCancelled else { break }
                let snapshot = await WhisperKitService.shared.librarySnapshot()
                await MainActor.run {
                    status = nextStatus
                    library = snapshot
                }
            }
        }
    }

    private func refreshLibrary() async {
        let service = WhisperKitService.shared
        let snapshot = await service.librarySnapshot()
        let currentStatus = await service.status
        await MainActor.run {
            library = snapshot
            status = currentStatus
        }
    }

    private func deleteModel(_ localModel: WhisperKitService.LocalModel) async {
        do {
            try await WhisperKitService.shared.deleteModel(localModel.id)
        } catch {
            await MainActor.run {
                status = .error(error.localizedDescription)
            }
        }

        await MainActor.run {
            if isSelected(localModel), let replacement = WhisperKitModelCatalog.presets.first?.id {
                modelSelection = replacement
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

    private func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
