import SwiftUI

struct CodeExecutionSheetView: View {
    @Binding var draft: CodeExecutionControls
    @Binding var openAIUseExistingContainer: Bool
    @Binding var openAIFileIDsDraft: String
    @Binding var draftError: String?

    let providerType: ProviderType?
    let isValid: Bool

    var onCancel: () -> Void
    var onSave: () -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    CodeExecutionBasicsCard(isEnabled: $draft.enabled)
                    providerSettingsCard
                    CodeExecutionSheetFooter(
                        draftError: draftError,
                        summaryText: summaryText,
                        providerDetailText: CodeExecutionSheetSupport.providerDetailText(for: providerType)
                    )
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Code Execution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave() {
                            onCancel()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 380, idealHeight: 460)
        .onChange(of: openAIUseExistingContainer) { _, useExisting in
            draftError = nil
            guard providerType == .openai || providerType == .openaiWebSocket else { return }

            var openAI = draft.openAI ?? OpenAICodeExecutionOptions()
            if useExisting {
                openAI.container = nil
            } else {
                openAI.existingContainerID = nil
                openAI.container = openAI.container ?? CodeExecutionContainer(type: "auto")
            }
            draft.openAI = openAI
        }
        .onChange(of: openAIFileIDsDraft) { _, _ in
            draftError = nil
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var providerSettingsCard: some View {
        switch providerType {
        case .openai, .openaiWebSocket:
            CodeExecutionOpenAISettingsCard(
                useExistingContainer: $openAIUseExistingContainer,
                existingContainerID: openAIContainerIDBinding,
                memoryLimit: openAIMemoryLimitBinding,
                fileIDsDraft: $openAIFileIDsDraft
            )
        case .anthropic:
            CodeExecutionAnthropicSettingsCard(containerID: anthropicContainerIDBinding)
        default:
            let info = CodeExecutionSheetSupport.providerSettingsInfo(for: providerType)
            CodeExecutionProviderInfoCard(title: info.title, message: info.body)
        }
    }

    // MARK: - Bindings

    private var openAIContainerIDBinding: Binding<String> {
        Binding(
            get: { draft.openAI?.existingContainerID ?? "" },
            set: { newValue in
                var openAI = draft.openAI ?? OpenAICodeExecutionOptions()
                openAI.existingContainerID = newValue
                draft.openAI = openAI
            }
        )
    }

    private var openAIMemoryLimitBinding: Binding<String> {
        Binding(
            get: { draft.openAI?.container?.memoryLimit ?? "" },
            set: { newValue in
                var openAI = draft.openAI ?? OpenAICodeExecutionOptions()
                var container = openAI.container ?? CodeExecutionContainer(type: "auto")
                container.type = "auto"
                container.memoryLimit = newValue.isEmpty ? nil : newValue
                openAI.container = container
                draft.openAI = openAI
            }
        )
    }

    private var anthropicContainerIDBinding: Binding<String> {
        Binding(
            get: { draft.anthropic?.containerID ?? "" },
            set: { newValue in
                var anthropic = draft.anthropic ?? AnthropicCodeExecutionOptions()
                anthropic.containerID = newValue
                draft.anthropic = anthropic
            }
        )
    }

    // MARK: - Text

    private var summaryText: String {
        CodeExecutionSheetSupport.summaryText(for: providerType)
    }

}
