import Foundation

enum CodeExecutionSheetSupport {
    struct PreparedDraft {
        let controls: CodeExecutionControls
        let openAIUseExistingContainer: Bool
        let openAIFileIDsDraft: String
    }

    struct AppliedDraft {
        let controls: CodeExecutionControls
        let errorMessage: String?

        var isValid: Bool {
            errorMessage == nil
        }
    }

    struct AppliedControls {
        let controls: GenerationControls
        let codeExecution: CodeExecutionControls
        let errorMessage: String?

        var isValid: Bool {
            errorMessage == nil
        }
    }
}
