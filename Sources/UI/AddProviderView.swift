import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ProviderType.openai.displayName
    @State private var providerType: ProviderType = .openai
    @State private var iconID: String? = LobeProviderIconCatalog.defaultIconID(for: .openai)
    @State private var baseURL = ProviderType.openai.defaultBaseURL ?? ""
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""

    @State private var isKeyVisible = false
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name, prompt: Text("e.g., \(providerType.displayName)"))
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Name is required.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                ProviderIconPickerField(
                    selectedIconID: $iconID,
                    defaultIconID: LobeProviderIconCatalog.defaultIconID(for: providerType)
                )

                Picker("Type", selection: $providerType) {
                    ForEach(ProviderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: providerType) { oldValue, newValue in
                    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed == oldValue.defaultBaseURL {
                        baseURL = newValue.defaultBaseURL ?? ""
                    }

                    let oldDefaultIconID = LobeProviderIconCatalog.defaultIconID(for: oldValue)
                    let currentIconID = iconID?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentIconID == nil || currentIconID?.isEmpty == true || currentIconID == oldDefaultIconID {
                        iconID = LobeProviderIconCatalog.defaultIconID(for: newValue)
                    }

                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedName.isEmpty || trimmedName == oldValue.displayName {
                        name = newValue.displayName
                    }
                }

                if providerType != .vertexai {
                    TextField("Base URL", text: $baseURL)
                        .help("Default endpoint is pre-filled.")
                }

                if providerType == .codexAppServer {
                    Text("Codex App Server expects a running `codex app-server --listen ws://127.0.0.1:4500` process. Recommended stable runtime: `codex` 0.107.0+.")
                        .jinInfoCallout()
                }

                if providerType == .openaiWebSocket {
                    Text("OpenAI WebSocket mode keeps a persistent connection to `/v1/responses` and can speed up tool-heavy workflows. Only one response can be in flight per connection.")
                        .jinInfoCallout()
                }

                if providerType == .cloudflareAIGateway {
                    Text("Recommended: use a Cloudflare API Token (BYOK mode). Fill in `{account_id}` and `{gateway_slug}`, keep the `/compat` Base URL, configure upstream provider keys in AI Gateway, then use model IDs like `openai/gpt-5` or `anthropic/claude-sonnet-4.5`.")
                        .jinInfoCallout()
                }

                if providerType == .zhipuCodingPlan {
                    Text("Use the dedicated Coding Plan endpoint: `https://open.bigmodel.cn/api/coding/paas/v4` (not the generic `/api/paas/v4`). Recommended model IDs: `glm-5`, `glm-4.7`.")
                        .jinInfoCallout()
                }

                if providerType == .githubCopilot {
                    Text("Uses GitHub Models' official inference API at `https://models.github.ai/inference`. Configure a GitHub token with GitHub Models access to use this provider.")
                        .jinInfoCallout()
                }

                switch providerType {
                case .codexAppServer:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Group {
                                if isKeyVisible {
                                    TextField("API Key (Optional)", text: $apiKey)
                                } else {
                                    SecureField("API Key (Optional)", text: $apiKey)
                                }
                            }
                            Button {
                                isKeyVisible.toggle()
                            } label: {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help(isKeyVisible ? "Hide API key" : "Show API key")
                            .disabled(apiKey.isEmpty)
                        }
                        Text("Leave blank to use ChatGPT account login in provider settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
                     .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
                     .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField(providerType == .githubCopilot ? "GitHub Token" : "API Key", text: $apiKey)
                            } else {
                                SecureField(providerType == .githubCopilot ? "GitHub Token" : "API Key", text: $apiKey)
                            }
                        }
                        Button {
                            isKeyVisible.toggle()
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(isKeyVisible ? "Hide API key" : "Show API key")
                        .disabled(apiKey.isEmpty)
                    }
                case .vertexai:
                    TextEditor(text: $serviceAccountJSON)
                        .frame(minHeight: 100)
                        .font(.system(.body, design: .monospaced))
                        .jinTextEditorField(cornerRadius: JinRadius.small)
                        .overlay(alignment: .topLeading) {
                            if serviceAccountJSON.isEmpty {
                                Text("Paste service account JSON here…")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let saveError {
                    Text(saveError)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Add Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProvider() }
                        .disabled(isAddDisabled)
                }
            }
            .frame(width: 500, height: 400)
        }
        #if os(macOS)
        .background(MovableWindowHelper())
        #endif
    }

    private func addProvider() {
        isSaving = true
        saveError = nil

        Task {
            do {
                let providerID = UUID().uuidString
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedServiceAccountJSON = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedIconID = iconID?.trimmingCharacters(in: .whitespacesAndNewlines)

                if providerType == .vertexai {
                    _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(trimmedServiceAccountJSON.utf8))
                }

                let isVertexAI = providerType == .vertexai
                let resolvedAPIKey: String? = isVertexAI ? nil : (trimmedAPIKey.isEmpty ? nil : trimmedAPIKey)
                let resolvedBaseURL: String? = isVertexAI ? nil : (trimmedBaseURL.isEmpty ? nil : trimmedBaseURL)

                let config = ProviderConfig(
                    id: providerID,
                    name: trimmedName,
                    type: providerType,
                    iconID: trimmedIconID?.isEmpty == false ? trimmedIconID : nil,
                    apiKey: resolvedAPIKey,
                    serviceAccountJSON: isVertexAI ? trimmedServiceAccountJSON : nil,
                    baseURL: resolvedBaseURL
                )

                let entity = try ProviderConfigEntity.fromDomain(config)

                await MainActor.run {
                    modelContext.insert(entity)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private var isAddDisabled: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isSaving else { return true }

        switch providerType {
        case .codexAppServer:
            return false
        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

