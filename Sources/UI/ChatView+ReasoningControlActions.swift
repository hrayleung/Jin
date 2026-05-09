import SwiftUI

// MARK: - Reasoning Control Actions

extension ChatView {

    func setReasoningOff() {
        ChatReasoningSupport.setReasoningOff(
            controls: &controls,
            reasoningMustRemainEnabled: reasoningMustRemainEnabled,
            selectedReasoningConfig: selectedReasoningConfig,
            providerType: providerType,
            modelID: activeModelID,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        persistControlsToConversation()
    }

    func setReasoningOn() {
        ChatReasoningSupport.setReasoningOn(
            controls: &controls,
            providerType: providerType,
            modelID: activeModelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        persistControlsToConversation()
    }

    func setReasoningEffort(_ effort: ReasoningEffort) {
        guard providerType != .anthropic else {
            openThinkingBudgetEditor()
            return
        }

        ChatReasoningSupport.setReasoningEffort(
            controls: &controls,
            effort: effort,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl
        )
        persistControlsToConversation()
    }

    func setAnthropicThinkingBudget(_ budgetTokens: Int) {
        ChatReasoningSupport.setAnthropicThinkingBudget(
            controls: &controls,
            budgetTokens: budgetTokens,
            providerType: providerType,
            modelID: activeModelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        persistControlsToConversation()
    }

    var thinkingBudgetDraftInt: Int? {
        ChatEditorDraftSupport.thinkingBudgetDraftInt(from: thinkingBudgetDraft)
    }

    var anthropicUsesAdaptiveThinking: Bool {
        ChatReasoningSupport.anthropicUsesAdaptiveThinking(
            providerType: providerType,
            modelID: activeModelID
        )
    }

    var anthropicUsesEffortMode: Bool {
        ChatReasoningSupport.anthropicUsesEffortMode(
            providerType: providerType,
            modelID: activeModelID
        )
    }

    var supportsAnthropicThinkingDisplayControl: Bool {
        ChatReasoningSupport.supportsAnthropicThinkingDisplayControl(
            providerType: providerType,
            modelID: activeModelID
        )
    }

    var anthropicEffortBinding: Binding<ReasoningEffort> {
        Binding(
            get: {
                ChatReasoningSupport.normalizedAnthropicEffort(
                    currentEffort: controls.reasoning?.effort,
                    defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high
                )
            },
            set: { newValue in
                ChatReasoningSupport.setAnthropicEffort(
                    controls: &controls,
                    newValue: newValue,
                    anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
                    modelID: activeModelID,
                    defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
                    defaultBudget: anthropicDefaultBudgetTokens
                )
                persistControlsToConversation()
            }
        )
    }

    var anthropicDefaultBudgetTokens: Int {
        selectedReasoningConfig?.defaultBudget ?? 1024
    }

    var maxTokensDraftInt: Int? {
        ChatEditorDraftSupport.maxTokensDraftInt(from: maxTokensDraft)
    }

    var isThinkingBudgetDraftValid: Bool {
        ChatEditorDraftSupport.isThinkingBudgetDraftValid(
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            providerType: providerType,
            modelID: activeModelID,
            thinkingBudgetDraft: thinkingBudgetDraft,
            maxTokensDraft: maxTokensDraft,
            currentMaxTokens: controls.maxTokens
        )
    }

    var thinkingBudgetValidationWarning: String? {
        ChatEditorDraftSupport.thinkingBudgetValidationWarning(
            providerType: providerType,
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            modelID: activeModelID,
            thinkingBudgetDraft: thinkingBudgetDraft,
            maxTokensDraft: maxTokensDraft,
            currentMaxTokens: controls.maxTokens
        )
    }

    func openThinkingBudgetEditor() {
        let prepared = ChatEditorDraftSupport.prepareThinkingBudgetEditorDraft(
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            budgetTokens: controls.reasoning?.budgetTokens ?? selectedReasoningConfig?.defaultBudget,
            defaultBudget: anthropicDefaultBudgetTokens,
            providerType: providerType,
            requestedMaxTokens: controls.maxTokens,
            modelID: activeModelID
        )
        thinkingBudgetDraft = prepared.thinkingBudgetDraft
        maxTokensDraft = prepared.maxTokensDraft
        anthropicThinkingDisplayDraft = ChatReasoningSupport.resolvedAnthropicThinkingDisplay(
            currentDisplay: controls.reasoning?.anthropicThinkingDisplay,
            providerType: providerType,
            modelID: activeModelID
        )
        showingThinkingBudgetSheet = true
    }

    func applyThinkingBudgetDraft() {
        let resolvedMaxTokensDraft = ChatReasoningSupport.applyThinkingBudgetDraft(
            controls: &controls,
            providerType: providerType,
            modelID: activeModelID,
            anthropicUsesAdaptiveThinking: anthropicUsesAdaptiveThinking,
            anthropicUsesEffortMode: anthropicUsesEffortMode,
            anthropicThinkingDisplay: supportsAnthropicThinkingDisplayControl ? anthropicThinkingDisplayDraft : nil,
            budgetTokens: thinkingBudgetDraftInt,
            maxTokens: maxTokensDraftInt,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
        if providerType == .anthropic, let resolvedMaxTokensDraft {
            maxTokensDraft = resolvedMaxTokensDraft
        }
        persistControlsToConversation()
    }

    func normalizeAnthropicReasoningAndMaxTokens() {
        ChatReasoningSupport.normalizeAnthropicReasoningAndMaxTokens(
            controls: &controls,
            providerType: providerType,
            modelID: activeModelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: anthropicDefaultBudgetTokens
        )
    }

    func setReasoningSummary(_ summary: ReasoningSummary) {
        ChatReasoningSupport.setReasoningSummary(
            controls: &controls,
            summary: summary,
            supportsReasoningSummaryControl: supportsReasoningSummaryControl,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .medium
        )
        persistControlsToConversation()
    }

    func updateReasoning(_ mutate: (inout ReasoningControls) -> Void) {
        ChatReasoningSupport.updateReasoning(
            controls: &controls,
            mutate: mutate
        )
    }
}
