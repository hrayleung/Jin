import Foundation

extension ModelCatalog {
    static let mistralRecords: [Record] = [
        Record(id: "mistral-medium-3.5", displayName: "Mistral Medium 3.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
    ]
}
