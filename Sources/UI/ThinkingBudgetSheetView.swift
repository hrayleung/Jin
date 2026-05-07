import SwiftUI

struct ThinkingBudgetSheetView: View {
    let usesAdaptiveThinking: Bool
    let usesEffortMode: Bool
    let modelID: String
    let modelMaxOutputTokens: Int?
    let supportedEffortLevels: [ReasoningEffort]

    @Binding var thinkingBudgetDraft: String
    @Binding var maxTokensDraft: String
    let supportsThinkingDisplayControl: Bool
    @Binding var thinkingDisplaySelection: AnthropicThinkingDisplay
    @Binding var effortSelection: ReasoningEffort

    var isValid: Bool
    var validationWarning: String?

    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ThinkingBudgetEditorCard(
                    usesAdaptiveThinking: usesAdaptiveThinking,
                    usesEffortMode: usesEffortMode,
                    modelMaxOutputTokens: modelMaxOutputTokens,
                    supportedEffortLevels: supportedEffortLevels,
                    supportsThinkingDisplayControl: supportsThinkingDisplayControl,
                    validationWarning: validationWarning,
                    thinkingBudgetDraft: $thinkingBudgetDraft,
                    maxTokensDraft: $maxTokensDraft,
                    thinkingDisplaySelection: $thinkingDisplaySelection,
                    effortSelection: $effortSelection
                )

                Spacer(minLength: JinSpacing.medium)
            }
            .padding(JinSpacing.large)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Thinking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(width: 480)
    }
}
