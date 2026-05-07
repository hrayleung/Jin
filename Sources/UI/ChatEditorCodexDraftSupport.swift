import Foundation

extension ChatEditorDraftSupport {
    static func normalizedCodexWorkingDirectoryPath(from raw: String) -> String? {
        CodexWorkingDirectoryPresetsStore.normalizedDirectoryPath(from: raw, requireExistingDirectory: true)
    }

    static func applyCodexSessionSettingsDraft(
        workingDirectoryDraft: String,
        sandboxModeDraft: CodexSandboxMode,
        personalityDraft: CodexPersonality?,
        controls: GenerationControls
    ) -> Result<(controls: GenerationControls, normalizedPath: String?), ChatEditorDraftError> {
        var updatedControls = controls

        guard let trimmed = workingDirectoryDraft.trimmedNonEmpty else {
            updatedControls.codexWorkingDirectory = nil
            updatedControls.codexSandboxMode = sandboxModeDraft
            updatedControls.codexPersonality = personalityDraft
            return .success((updatedControls, nil))
        }

        guard let normalized = normalizedCodexWorkingDirectoryPath(from: trimmed) else {
            return .failure(.message("Choose an existing local folder (absolute path or ~/path)."))
        }

        updatedControls.codexWorkingDirectory = normalized
        updatedControls.codexSandboxMode = sandboxModeDraft
        updatedControls.codexPersonality = personalityDraft
        return .success((updatedControls, normalized))
    }
}
