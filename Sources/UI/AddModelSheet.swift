import SwiftUI

// MARK: - OpenRouter Usage Types

enum OpenRouterUsageStatus: Equatable {
    case idle
    case loading
    case observed
    case failure(String)
}

struct OpenRouterKeyUsage: Equatable {
    let used: Double
    let remaining: Double?

    func remainingText(formatter: (Double) -> String) -> String {
        guard let remaining else { return "Unavailable" }
        return formatter(remaining)
    }
}

struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

struct OpenRouterKeyData: Decodable {
    let usage: Double?
    let limit: Double?
    let limitRemaining: Double?
}

struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

struct OpenRouterCreditsData: Decodable {
    let totalCredits: Double?
    let totalUsage: Double?
}

// MARK: - Add Model Sheet

struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerType: ProviderType?
    let onAdd: (ModelInfo) -> Void

    @State private var nickname = ""
    @State private var modelID = ""
    @State private var customOverrides: ModelOverrides?
    @State private var editingModel: ModelInfo?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: JinSpacing.large) {
                        headerSection
                        identitySection
                        settingsSection
                    }
                    .padding(JinSpacing.xLarge)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background {
                LinearGradient(
                    colors: [
                        JinSemanticColor.detailSurface,
                        JinSemanticColor.surface.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Add Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addModel() }
                        .disabled(!canAddModel)
                }
            }
        }
        .sheet(item: $editingModel) { model in
            ModelSettingsSheet(
                model: model,
                providerType: providerType,
                onSave: { updated in
                    customOverrides = updated.overrides
                }
            )
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedModelName: String {
        trimmedNickname.isEmpty ? trimmedModelID : trimmedNickname
    }

    private var canAddModel: Bool {
        !trimmedModelID.isEmpty
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Create a custom model entry")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Nickname is optional. Model ID should exactly match the provider identifier.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            Text("Identity")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                fieldBlock(
                    title: "Nickname",
                    prompt: "Optional display name",
                    helperText: "Leave empty to use Model ID as the display name.",
                    text: $nickname,
                    monospaced: false
                )

                fieldBlock(
                    title: "Model ID",
                    prompt: "Required (for example: gpt-5.2-codex)",
                    helperText: "Used for API calls and capability inference.",
                    text: $modelID,
                    monospaced: true
                )
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            HStack(spacing: JinSpacing.small) {
                Label("Advanced Overrides", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if customOverrides != nil {
                    Text("Configured")
                        .jinTagStyle(foreground: .accentColor)
                }
            }

            Text("Fine-tune capabilities, token limits, and reasoning behavior for this model.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openModelSettings) {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: customOverrides == nil ? "gearshape" : "slider.horizontal.3")
                        .foregroundStyle(canAddModel ? Color.accentColor : Color.secondary)
                    Text(customOverrides == nil ? "Configure Model Settings" : "Edit Model Settings")
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, JinSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .fill(canAddModel ? JinSemanticColor.accentSurface : JinSemanticColor.subtleSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)
                    .stroke(
                        canAddModel ? Color.accentColor.opacity(0.32) : JinSemanticColor.separator.opacity(0.5),
                        lineWidth: JinStrokeWidth.hairline
                    )
            }
            .disabled(!canAddModel)

            if !canAddModel {
                Label("Enter Model ID first to configure settings.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.large)
    }

    private func fieldBlock(
        title: String,
        prompt: String,
        helperText: String,
        text: Binding<String>,
        monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            TextField("", text: text, prompt: Text(prompt))
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textFieldStyle(.plain)
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .fill(JinSemanticColor.textSurface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                        .stroke(JinSemanticColor.separator.opacity(0.55), lineWidth: JinStrokeWidth.hairline)
                }
                .onSubmit {
                    if canAddModel {
                        addModel()
                    }
                }

            Text(helperText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openModelSettings() {
        guard canAddModel else { return }
        var draft = makeModelInfo(id: trimmedModelID, name: resolvedModelName)
        draft.overrides = customOverrides
        editingModel = draft
    }

    private func addModel() {
        guard canAddModel else { return }
        var model = makeModelInfo(id: trimmedModelID, name: resolvedModelName)
        model.overrides = customOverrides
        onAdd(model)
        dismiss()
    }

    private func makeModelInfo(id: String, name: String) -> ModelInfo {
        let lower = id.lowercased()
        let openAIReasoningModels: Set<String> = ["gpt-5", "gpt-5.2", "gpt-5.2-2025-12-11", "gpt-5.3-codex", "o3", "o4"]
        let openAIVisionModels: Set<String> = ["gpt-5", "gpt-5.2", "gpt-5.2-2025-12-11", "gpt-5.3-codex", "gpt-4o", "o3", "o4"]
        let fireworksVisionModels: Set<String> = [
            "fireworks/kimi-k2p5",
            "accounts/fireworks/models/kimi-k2p5",
            "fireworks/qwen3-omni-30b-a3b-instruct",
            "accounts/fireworks/models/qwen3-omni-30b-a3b-instruct",
            "fireworks/qwen3-omni-30b-a3b-thinking",
            "accounts/fireworks/models/qwen3-omni-30b-a3b-thinking",
        ]
        let geminiTextModels: Set<String> = ["gemini-3", "gemini-3-pro", "gemini-3-pro-preview", "gemini-3.1-pro-preview", "gemini-3-flash-preview"]
        let geminiImageModels: Set<String> = ["gemini-3-pro-image-preview", "gemini-2.5-flash-image"]
        let vertexGemini3TextModels: Set<String> = ["gemini-3", "gemini-3-pro", "gemini-3-pro-preview", "gemini-3.1-pro-preview", "gemini-3-flash-preview"]
        let vertexGemini25TextModels: Set<String> = ["gemini-2.5", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"]
        let anthropicExtendedContextModels: Set<String> = [
            "claude-opus-4",
            "claude-sonnet-4",
            "claude-haiku-4",
            "claude-opus-4-6",
            "claude-sonnet-4-6",
            "claude-opus-4-5-20251101",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001",
        ]
        let xAIImageModels: Set<String> = ["grok-imagine-image", "grok-imagine-image-pro", "grok-2-image-1212"]
        let xAIVideoModels: Set<String> = ["grok-imagine-video"]
        let xAIReasoningChatModels: Set<String> = ["grok-4-1", "grok-4-1-fast", "grok-4-1-fast-non-reasoning", "grok-4-1-fast-reasoning"]
        let perplexityReasoningModels: Set<String> = ["sonar-reasoning", "sonar-reasoning-pro", "sonar-deep-research"]
        let perplexityVisionModels: Set<String> = ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro"]
        let perplexityNativePDFModels: Set<String> = ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro", "sonar-deep-research"]
        let perplexityExtendedContextModels: Set<String> = ["sonar-pro"]

        var caps: ModelCapability = [.streaming, .toolCalling]
        var contextWindow = 128000
        var reasoningConfig: ModelReasoningConfig?

        switch providerType {
        case .openai?, .openaiWebSocket?:
            if openAIVisionModels.contains(lower) {
                caps.insert(.vision)
                caps.insert(.promptCaching)
                if let providerType,
                   JinModelSupport.supportsNativePDF(providerType: providerType, modelID: lower) {
                    caps.insert(.nativePDF)
                }
            }
            if openAIReasoningModels.contains(lower) {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }
            if ["gpt-5", "gpt-5.2", "gpt-5.2-2025-12-11", "gpt-5.3-codex"].contains(lower) {
                contextWindow = 400_000
            }

        case .fireworks?:
            if lower == "fireworks/minimax-m2p5" || lower == "accounts/fireworks/models/minimax-m2p5" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 196_600
            } else if lower == "fireworks/minimax-m2p1" || lower == "accounts/fireworks/models/minimax-m2p1" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 204_800
            } else if lower == "fireworks/minimax-m2" || lower == "accounts/fireworks/models/minimax-m2" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 196_600
            } else if lower == "fireworks/kimi-k2p5" || lower == "accounts/fireworks/models/kimi-k2p5" {
                caps.insert(.vision)
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 262_100
            } else if lower == "fireworks/glm-5" || lower == "accounts/fireworks/models/glm-5" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 202_800
            } else if lower == "fireworks/glm-4p7" || lower == "accounts/fireworks/models/glm-4p7" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 202_800
            }
            if fireworksVisionModels.contains(lower) {
                caps.insert(.vision)
            }

        case .cerebras?:
            if lower == "zai-glm-4.7" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .toggle)
                contextWindow = 131_072
            }

        case .gemini?:
            if lower == "gemini-3-pro-image-preview" {
                caps = [.streaming, .vision, .reasoning, .imageGeneration]
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
                contextWindow = 65_536
            } else if lower == "gemini-2.5-flash-image" {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
                contextWindow = 32_768
            } else if geminiTextModels.contains(lower) {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
                contextWindow = 1_048_576
            } else if geminiImageModels.contains(lower) {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
            }

        case .vertexai?:
            if lower == "gemini-3-pro-image-preview" {
                caps = [.streaming, .vision, .reasoning, .imageGeneration]
                reasoningConfig = nil
                contextWindow = 65_536
            } else if lower == "gemini-2.5-flash-image" {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
                contextWindow = 32_768
            } else if geminiImageModels.contains(lower) {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
            } else if vertexGemini25TextModels.contains(lower) {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
                contextWindow = 1_048_576
            } else if vertexGemini3TextModels.contains(lower) {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 1_048_576
            }

        case .anthropic?:
            if anthropicExtendedContextModels.contains(lower) {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.promptCaching)
                caps.insert(.nativePDF)
                contextWindow = 200_000
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }

        case .xai?:
            if xAIVideoModels.contains(lower) {
                caps = [.videoGeneration]
                reasoningConfig = nil
                contextWindow = 32_768
            } else if xAIImageModels.contains(lower) {
                caps = [.imageGeneration]
                reasoningConfig = nil
                if lower == "grok-imagine-image" || lower == "grok-imagine-image-pro" {
                    contextWindow = 32_768
                } else if lower == "grok-2-image-1212" {
                    contextWindow = 131_072
                }
            } else if xAIReasoningChatModels.contains(lower) {
                contextWindow = 2_000_000
            }

        case .perplexity?:
            if perplexityReasoningModels.contains(lower) {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            if perplexityVisionModels.contains(lower) {
                caps.insert(.vision)
            }
            if perplexityNativePDFModels.contains(lower) {
                caps.insert(.nativePDF)
            }
            if perplexityExtendedContextModels.contains(lower) {
                contextWindow = 200_000
            }

        case .codexAppServer?, .openaiCompatible?, .openrouter?, .groq?, .cohere?, .mistral?, .deepinfra?, .deepseek?, .none:
            break
        }

        if supportsAudioInputModelID(lowerModelID: lower, providerType: providerType) {
            caps.insert(.audio)
        }

        if reasoningConfig == nil,
           let inferredReasoning = ModelCapabilityRegistry.defaultReasoningConfig(
            for: providerType,
            modelID: id
           ) {
            caps.insert(.reasoning)
            reasoningConfig = inferredReasoning
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private func supportsAudioInputModelID(lowerModelID: String, providerType: ProviderType?) -> Bool {
        let openAIAudioInputModelIDs: Set<String> = [
            "gpt-4o-audio-preview",
            "gpt-4o-audio-preview-2024-10-01",
            "gpt-4o-mini-audio-preview",
            "gpt-4o-mini-audio-preview-2024-12-17",
            "gpt-4o-realtime-preview",
            "gpt-4o-realtime-preview-2024-10-01",
            "gpt-4o-realtime-preview-2024-12-17",
            "gpt-4o-mini-realtime-preview",
            "gpt-4o-mini-realtime-preview-2024-12-17",
            "gpt-realtime",
            "gpt-realtime-mini",
        ]
        let mistralAudioInputModelIDs: Set<String> = [
            "voxtral-large-latest",
            "voxtral-small-latest",
        ]
        let geminiAudioInputModelIDs: Set<String> = [
            "gemini-3",
            "gemini-3-pro",
            "gemini-3-pro-preview",
            "gemini-3.1-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemini-2.0-flash",
            "gemini-2.0-flash-lite",
        ]
        let qwenAudioInputModelIDs: Set<String> = [
            "qwen3-asr-4b",
            "qwen3-asr-0.6b",
            "qwen3-omni-30b-a3b-instruct",
            "qwen3-omni-30b-a3b-thinking",
        ]
        let fireworksAudioInputModelIDs: Set<String> = [
            "qwen3-asr-4b",
            "qwen3-asr-0.6b",
            "qwen3-omni-30b-a3b-instruct",
            "qwen3-omni-30b-a3b-thinking",
            "fireworks/qwen3-asr-4b",
            "fireworks/qwen3-asr-0.6b",
            "fireworks/qwen3-omni-30b-a3b-instruct",
            "fireworks/qwen3-omni-30b-a3b-thinking",
            "accounts/fireworks/models/qwen3-asr-4b",
            "accounts/fireworks/models/qwen3-asr-0.6b",
            "accounts/fireworks/models/qwen3-omni-30b-a3b-instruct",
            "accounts/fireworks/models/qwen3-omni-30b-a3b-thinking",
        ]
        let compatibleAudioInputModelIDs = openAIAudioInputModelIDs
            .union(mistralAudioInputModelIDs)
            .union(qwenAudioInputModelIDs)
            .union(geminiAudioInputModelIDs)

        switch providerType {
        case .openai?, .openaiWebSocket?:
            return openAIAudioInputModelIDs.contains(lowerModelID)

        case .mistral?:
            return mistralAudioInputModelIDs.contains(lowerModelID)

        case .gemini?, .vertexai?:
            return geminiAudioInputModelIDs.contains(lowerModelID)

        case .openaiCompatible?, .openrouter?, .deepinfra?:
            return compatibleAudioInputModelIDs.contains(lowerModelID)

        case .fireworks?:
            return fireworksAudioInputModelIDs.contains(lowerModelID)

        case .anthropic?, .perplexity?, .groq?, .cohere?, .xai?, .deepseek?, .cerebras?, .codexAppServer?, .none:
            return false
        }
    }
}
