import SwiftUI
import SwiftData

// MARK: - Model Controls

extension ChatView {

    var providerType: ProviderType? {
        if let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
           let providerType = ProviderType(rawValue: provider.typeRaw) {
            return providerType
        }

        // Fallback: for the built-in providers, `providerID` matches the provider type.
        return ProviderType(rawValue: conversationEntity.providerID)
    }

    func openImageGenerationEditor() {
        let prepared = ChatEditorDraftSupport.prepareImageGenerationEditorDraft(
            current: controls.imageGeneration,
            supportedAspectRatios: supportedCurrentModelImageAspectRatios,
            supportedImageSizes: supportedCurrentModelImageSizes
        )
        imageGenerationDraft = prepared.draft
        imageGenerationSeedDraft = prepared.seedDraft
        imageGenerationCompressionQualityDraft = prepared.compressionQualityDraft
        imageGenerationDraftError = nil
        showingImageGenerationSheet = true
    }

    func openCodexSessionSettingsEditor() {
        codexWorkingDirectoryDraft = codexWorkingDirectory ?? ""
        codexWorkingDirectoryDraftError = nil
        codexSandboxModeDraft = controls.codexSandboxMode
        codexPersonalityDraft = controls.codexPersonality
        showingCodexSessionSettingsSheet = true
    }

    func pickCodexWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = "Choose a working directory to send as Codex `cwd`."

        if let existing = normalizedCodexWorkingDirectoryPath(from: codexWorkingDirectoryDraft) {
            panel.directoryURL = URL(fileURLWithPath: existing, isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        codexWorkingDirectoryDraft = selectedURL.path
        codexWorkingDirectoryDraftError = nil
    }

    func applyCodexSessionSettingsDraft() {
        switch ChatEditorDraftSupport.applyCodexSessionSettingsDraft(
            workingDirectoryDraft: codexWorkingDirectoryDraft,
            sandboxModeDraft: codexSandboxModeDraft,
            personalityDraft: codexPersonalityDraft,
            controls: controls
        ) {
        case .success(let result):
            controls = result.controls
            persistControlsToConversation()
            codexWorkingDirectoryDraft = result.normalizedPath ?? ""
            codexWorkingDirectoryDraftError = nil
            showingCodexSessionSettingsSheet = false
        case .failure(let error):
            codexWorkingDirectoryDraftError = error.localizedDescription
        }
    }

    func resolveCodexInteraction(_ item: PendingCodexInteraction, response: CodexInteractionResponse) {
        Task {
            await item.request.resolve(response)
        }
        pendingCodexInteractions.removeAll { $0.id == item.id }
    }

    func resolveAgentApproval(_ item: PendingAgentApproval, choice: AgentApprovalChoice) {
        Task {
            await item.request.resolve(choice)
        }
        pendingAgentApprovals.removeAll { $0.id == item.id }
    }

    func normalizedCodexWorkingDirectoryPath(from raw: String) -> String? {
        ChatEditorDraftSupport.normalizedCodexWorkingDirectoryPath(from: raw)
    }

    var isImageGenerationDraftValid: Bool {
        ChatEditorDraftSupport.isImageGenerationDraftValid(
            seedDraft: imageGenerationSeedDraft,
            compressionQualityDraft: imageGenerationCompressionQualityDraft
        )
    }

    @discardableResult
    func applyImageGenerationDraft() -> Bool {
        switch ChatEditorDraftSupport.applyImageGenerationDraft(
            draft: imageGenerationDraft,
            seedDraft: imageGenerationSeedDraft,
            compressionQualityDraft: imageGenerationCompressionQualityDraft,
            supportsCurrentModelImageSizeControl: supportsCurrentModelImageSizeControl,
            supportedCurrentModelImageSizes: supportedCurrentModelImageSizes,
            supportedCurrentModelImageAspectRatios: supportedCurrentModelImageAspectRatios,
            providerType: providerType
        ) {
        case .success(let draft):
            controls.imageGeneration = draft
            persistControlsToConversation()
            imageGenerationDraftError = nil
            return true
        case .failure(let error):
            imageGenerationDraftError = error.localizedDescription
            return false
        }
    }

    func openContextCacheEditor() {
        let prepared = ChatAuxiliaryControlSupport.prepareContextCacheEditorDraft(
            current: controls.contextCache,
            providerType: providerType,
            supportsContextCacheTTL: supportsContextCacheTTL
        )
        contextCacheDraft = prepared.draft
        contextCacheTTLPreset = prepared.ttlPreset
        contextCacheCustomTTLDraft = prepared.customTTLDraft
        contextCacheMinTokensDraft = prepared.minTokensDraft
        contextCacheAdvancedExpanded = prepared.advancedExpanded
        contextCacheDraftError = nil
        showingContextCacheSheet = true
    }
}
