import Foundation

enum ChatEditorDraftError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

struct PreparedImageGenerationEditorDraft {
    let draft: ImageGenerationControls
    let seedDraft: String
    let compressionQualityDraft: String
}

struct PreparedThinkingBudgetEditorDraft {
    let thinkingBudgetDraft: String
    let maxTokensDraft: String
}

enum ChatEditorDraftSupport {}
