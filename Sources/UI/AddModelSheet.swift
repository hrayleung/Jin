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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nickname", text: $nickname)
                TextField("Model ID", text: $modelID)
                    .font(.system(.body, design: .monospaced))
            }
            .navigationTitle("Add Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameToUse = trimmedName.isEmpty ? trimmedID : trimmedName

                        onAdd(makeModelInfo(id: trimmedID, name: nameToUse))
                        dismiss()
                    }
                    .disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
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
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
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
            if lower.contains("imagine-image")
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

        case .openai?, .openaiCompatible?, .openrouter?, .anthropic?, .groq?, .cohere?, .mistral?, .deepinfra?, .deepseek?, .none:
            break
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }
}
