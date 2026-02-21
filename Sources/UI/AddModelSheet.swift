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

        var caps: ModelCapability = [.streaming, .toolCalling]
        var contextWindow = 128000
        var reasoningConfig: ModelReasoningConfig?

        switch providerType {
        case .fireworks?:
            if lower == "fireworks/minimax-m2p5" || lower == "accounts/fireworks/models/minimax-m2p5" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 204_800
            } else if lower == "fireworks/minimax-m2p1" || lower == "accounts/fireworks/models/minimax-m2p1" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 204_800
            } else if lower == "fireworks/minimax-m2" || lower == "accounts/fireworks/models/minimax-m2" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 196_600
            } else if lower.hasPrefix("fireworks/minimax-m2") || lower.hasPrefix("accounts/fireworks/models/minimax-m2") {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
                contextWindow = 204_800
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
            if lower.contains("qwen3-omni") {
                caps.insert(.vision)
            }

        case .cerebras?:
            if lower == "zai-glm-4.7" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .toggle)
            }

        case .gemini?:
            if lower.contains("gemini-3-pro-image") {
                caps = [.streaming, .vision, .reasoning, .imageGeneration]
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            } else if lower.contains("-image") {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
            } else if lower.contains("gemini-3") {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }

        case .vertexai?:
            if lower.contains("gemini-3-pro-image") {
                caps = [.streaming, .vision, .reasoning, .imageGeneration]
                reasoningConfig = nil
            } else if lower.contains("-image") {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
            } else if lower.contains("gemini-2.5") {
                caps.insert(.vision)
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            } else if lower.contains("gemini-3") {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }

        case .xai?:
            if lower.contains("imagine-video")
                || lower.hasSuffix("-video")
                || lower.contains("grok-video")
                || lower.contains("video-generation") {
                caps = [.videoGeneration]
                reasoningConfig = nil
            } else if lower.contains("imagine-image")
                || lower.contains("grok-2-image")
                || lower.hasSuffix("-image") {
                caps = [.imageGeneration]
                reasoningConfig = nil
            }

        case .perplexity?:
            if lower.contains("reasoning") || lower.contains("deep-research") {
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            if lower.contains("sonar") {
                caps.insert(.vision)
                caps.insert(.nativePDF)
            }

        case .openai?, .codexAppServer?, .openaiCompatible?, .openrouter?, .anthropic?, .groq?, .cohere?, .mistral?, .deepinfra?, .deepseek?, .none:
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
        switch providerType {
        case .openai?:
            return lowerModelID.contains("gpt-audio")
                || lowerModelID.contains("audio-preview")
                || lowerModelID.contains("realtime")

        case .mistral?:
            return lowerModelID.contains("voxtral")
                && lowerModelID != "voxtral-mini-2602"
                && !lowerModelID.contains("transcribe")

        case .gemini?, .vertexai?:
            return lowerModelID.contains("gemini-")
                && !lowerModelID.contains("-image")
                && !lowerModelID.contains("imagen")

        case .openaiCompatible?, .openrouter?, .deepinfra?:
            if lowerModelID.contains("gpt-audio")
                || lowerModelID.contains("audio-preview")
                || lowerModelID.contains("realtime")
                || lowerModelID.contains("voxtral")
                || lowerModelID.contains("qwen3-asr")
                || lowerModelID.contains("qwen3-omni") {
                return true
            }

            if (lowerModelID.contains("gemini-2.0")
                || lowerModelID.contains("gemini-2.5")
                || lowerModelID.contains("gemini-3"))
                && !lowerModelID.contains("-image")
                && !lowerModelID.contains("imagen") {
                return true
            }

            return false

        case .fireworks?:
            return lowerModelID.contains("qwen3-asr")
                || lowerModelID.contains("qwen3-omni")

        case .anthropic?, .perplexity?, .groq?, .cohere?, .xai?, .deepseek?, .cerebras?, .codexAppServer?, .none:
            return false
        }
    }
}
