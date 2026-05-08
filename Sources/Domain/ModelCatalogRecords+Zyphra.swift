import Foundation

// MARK: - Zyphra Cloud Records
//
// Listed at https://cloud.zyphra.com/docs#description/available-models.
// Confirmed model IDs use HuggingFace-style namespacing (e.g. deepseek-ai/DeepSeek-V3.2).
// Capabilities and context windows mirror the same models seeded for upstream
// providers (DeepInfra, Together) so the picker presents consistent metadata.

extension ModelCatalog {

    static let zyphraRecords: [Record] = [
        Record(id: "Zyphra/ZAYA1-8B", displayName: "ZAYA1-8B",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 131_072,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
               isFullySupported: true, isSeeded: true),
        Record(id: "moonshotai/Kimi-K2.6", displayName: "Kimi K2.6",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "zai-org/GLM-5.1", displayName: "GLM-5.1",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 202_752,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        Record(id: "deepseek-ai/DeepSeek-V3.2", displayName: "DeepSeek V3.2",
               capabilities: [.streaming, .toolCalling, .reasoning],
               contextWindow: 163_840,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
    ]
}
