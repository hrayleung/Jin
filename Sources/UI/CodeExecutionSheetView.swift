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
                    summaryCard
                    providerSettingsCard

                    if let draftError {
                        Text(draftError)
                            .jinInlineErrorText()
                            .padding(.horizontal, JinSpacing.small)
                            .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                    } else {
                        guidanceCard
                    }
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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Toggle("Enable code execution", isOn: $draft.enabled)
                .toggleStyle(.switch)

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

            fieldRow(
                "Mode",
                hint: "Use an auto-created container for each request, or reuse an existing container by ID."
            ) {
                Picker("Mode", selection: $openAIUseExistingContainer) {
                    Text("Auto").tag(false)
                    Text("Existing").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            if openAIUseExistingContainer {
                fieldRow(
                    "Container ID",
                    hint: "Reuse an existing OpenAI container. Jin sends this value directly as the code_interpreter container reference."
                ) {
                    TextField(text: openAIContainerIDBinding, prompt: Text("cntr_...")) {
                        EmptyView()
                    }
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }
            } else {
                fieldRow(
                    "Memory limit",
                    hint: "Optional. OpenAI supports 1g, 4g, 16g, or 64g for auto-created containers."
                ) {
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

                fieldRow(
                    "Extra file IDs",
                    hint: "Optional. One file ID per line or comma-separated. These are copied into the auto-created container in addition to conversation attachments."
                ) {
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

            fieldRow(
                "Container ID",
                hint: "Optional. Reuse an existing Anthropic code execution container between requests."
            ) {
                TextField(text: anthropicContainerIDBinding, prompt: Text("container_...")) {
                    EmptyView()
                }
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            }

            Text("When code execution is enabled, Jin sends supported uploaded documents as container uploads so Claude can access them directly inside the execution sandbox.")
                .jinInfoCallout()
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private func googleInfoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text(title)
                .font(.headline)

            Text(body)
                .jinInfoCallout()
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    @ViewBuilder
    private var guidanceCard: some View {
        switch providerType {
        case .openai, .openaiWebSocket:
            Text("OpenAI code execution uses the Responses API code_interpreter tool. Auto mode configures the request-level container; Existing mode reuses a pre-created container ID.")
                .jinInfoCallout()
        case .anthropic:
            Text("Anthropic code execution uses the Messages API code_execution_20250825 tool. Reusing a container preserves files and state across requests until the container expires.")
                .jinInfoCallout()
        default:
            Text("Configuration changes apply only to this conversation.")
                .jinInfoCallout()
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

    @ViewBuilder
    private func fieldRow<Control: View>(
        _ title: String,
        hint: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
