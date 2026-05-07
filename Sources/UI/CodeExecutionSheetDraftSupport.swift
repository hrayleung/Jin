import Foundation

extension CodeExecutionSheetSupport {
    static func parsedOpenAIFileIDsDraft(_ draft: String) -> [String] {
        draft
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .compactMap { String($0).trimmedNonEmpty }
    }

    static func preparedDraft(
        current: CodeExecutionControls?,
        isEnabled: Bool,
        providerType: ProviderType?
    ) -> PreparedDraft {
        var draft = current ?? CodeExecutionControls(enabled: isEnabled)

        let openAISettings = draft.openAI?.normalized()
        let useExistingContainer = openAISettings?.normalizedExistingContainerID != nil
        let fileIDsDraft = openAISettings?.container?.normalizedFileIDs?.joined(separator: "\n") ?? ""

        if providerSupportsOpenAIContainerSettings(providerType),
           !useExistingContainer,
           draft.openAI == nil {
            draft.openAI = OpenAICodeExecutionOptions(
                container: CodeExecutionContainer(type: "auto")
            )
        }

        return PreparedDraft(
            controls: draft,
            openAIUseExistingContainer: useExistingContainer,
            openAIFileIDsDraft: fileIDsDraft
        )
    }

    static func appliedDraft(
        _ draft: CodeExecutionControls,
        providerType: ProviderType?,
        openAIUseExistingContainer: Bool,
        openAIFileIDsDraft: String
    ) -> AppliedDraft {
        var updated = draft

        if providerSupportsOpenAIContainerSettings(providerType) {
            var openAI = updated.openAI ?? OpenAICodeExecutionOptions()

            if openAIUseExistingContainer {
                guard let existingContainerID = openAI.normalizedExistingContainerID else {
                    return AppliedDraft(
                        controls: draft,
                        errorMessage: "Enter an OpenAI container ID."
                    )
                }
                openAI.existingContainerID = existingContainerID
                openAI.container = nil
            } else {
                var container = openAI.container ?? CodeExecutionContainer(type: "auto")
                container.type = "auto"
                container.fileIDs = parsedOpenAIFileIDsDraft(openAIFileIDsDraft)
                openAI.container = container.normalized()
                openAI.existingContainerID = nil
            }

            updated.openAI = openAI.normalized()
        }

        if providerType == .anthropic {
            updated.anthropic = updated.anthropic?.normalized()
        }

        return AppliedDraft(controls: updated, errorMessage: nil)
    }

    static func appliedControls(
        _ draft: CodeExecutionControls,
        to controls: GenerationControls,
        providerType: ProviderType?,
        openAIUseExistingContainer: Bool,
        openAIFileIDsDraft: String
    ) -> AppliedControls {
        let applied = appliedDraft(
            draft,
            providerType: providerType,
            openAIUseExistingContainer: openAIUseExistingContainer,
            openAIFileIDsDraft: openAIFileIDsDraft
        )

        guard applied.isValid else {
            return AppliedControls(
                controls: controls,
                codeExecution: applied.controls,
                errorMessage: applied.errorMessage
            )
        }

        var updatedControls = controls
        updatedControls.codeExecution = applied.controls
        return AppliedControls(
            controls: updatedControls,
            codeExecution: applied.controls,
            errorMessage: nil
        )
    }
}
