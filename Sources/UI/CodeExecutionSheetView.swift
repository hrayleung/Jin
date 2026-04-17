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
                    basicsCard
                    providerSettingsCard
                    footerCard
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

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text("Basics")
                    .font(.headline)
                Spacer()
                Text(draft.enabled ? "On" : "Off")
                    .jinTagStyle(foreground: draft.enabled ? .accentColor : .secondary)
            }

            Toggle("Enable code execution", isOn: $draft.enabled)
                .toggleStyle(.switch)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    @ViewBuilder
    private var providerSettingsCard: some View {
        switch providerType {
        case .openai, .openaiWebSocket:
            openAISettingsCard
        case .anthropic, .claudeManagedAgents:
            anthropicSettingsCard
        case .gemini:
            googleInfoCard(
                title: "Gemini API (AI Studio)",
                body: "Gemini code execution has no request-level tuning fields in Jin. Supported Files API uploads can be combined with code execution after they become ACTIVE. Spreadsheet files like .xlsx are not sent as mounted files; Jin falls back to extracted text when possible."
            )
        case .vertexai:
            googleInfoCard(
                title: "Vertex AI",
                body: "Vertex AI code execution has no request-level tuning fields in Jin. Vertex AI documents remain prompt context only: the code execution sandbox does not support file I/O."
            )
        case .xai:
            googleInfoCard(
                title: "xAI",
                body: "xAI code execution currently has no additional request parameters exposed in Jin."
            )
        case .none, .codexAppServer, .githubCopilot, .openaiCompatible,
             .cloudflareAIGateway, .vercelAIGateway, .openrouter, .perplexity, .groq, .cohere,
             .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks,
             .cerebras, .sambanova, .morphllm, .opencodeGo:
            googleInfoCard(
                title: providerType?.displayName ?? "Provider",
                body: "No provider-specific code execution parameters are exposed for this provider."
            )
        }
    }

    private var openAISettingsCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("OpenAI Container")
                .font(.headline)

            JinFormFieldRow("Mode") {
                Picker("Mode", selection: $openAIUseExistingContainer) {
                    Text("Auto").tag(false)
                    Text("Existing").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            if openAIUseExistingContainer {
                JinFormFieldRow("Container ID", supportingText: "Reuses an existing container.") {
                    TextField(text: openAIContainerIDBinding, prompt: Text("cntr_...")) {
                        EmptyView()
                    }
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }
            } else {
                JinFormFieldRow("Memory limit", supportingText: "Optional.") {
                    Picker("Memory limit", selection: openAIMemoryLimitBinding) {
                        Text("Provider default").tag("")
                        Text("1g").tag("1g")
                        Text("4g").tag("4g")
                        Text("16g").tag("16g")
                        Text("64g").tag("64g")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }

                JinFormFieldRow("Extra file IDs", supportingText: "One file ID per line or comma-separated.") {
                    TextEditor(text: $openAIFileIDsDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 84)
                        .jinTextEditorField(cornerRadius: JinRadius.small)
                }
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var anthropicSettingsCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text("Anthropic Container")
                .font(.headline)

            JinFormFieldRow("Container ID", supportingText: "Optional.") {
                TextField(text: anthropicContainerIDBinding, prompt: Text("container_...")) {
                    EmptyView()
                }
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private func googleInfoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("No extra settings")
                    .jinTagStyle()
            }

            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if let draftError {
                Text(draftError)
                    .jinInlineErrorText()
                    .padding(.horizontal, JinSpacing.small)
                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
            }

            JinDetailsDisclosure {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch providerType {
                case .openai, .openaiWebSocket:
                    Text("Auto creates a request-scoped container. Existing sends a pre-created container reference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .anthropic, .claudeManagedAgents:
                    Text("Claude can reuse a container between requests. Supported uploads are mounted into the sandbox.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    Text("Configuration changes apply only to this conversation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        switch providerType {
        case .openai, .openaiWebSocket:
            return "OpenAI supports request-level container configuration for code interpreter, including memory limits, extra file IDs, and explicit container reuse."
        case .anthropic:
            return "Anthropic supports reusable code execution containers. Supported uploaded files can be attached directly to the sandbox."
        case .gemini:
            return "Gemini supports code execution, but there are no extra request fields to tune here."
        case .vertexai:
            return "Vertex AI supports code execution, but the sandbox does not support file I/O."
        default:
            return "Provider-native code execution lets the model write and run code inside a managed sandbox."
        }
    }

}
