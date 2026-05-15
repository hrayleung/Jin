import Foundation

enum ManagedAgentInteractionSheetSupport {
    static let requiredAnswerValidationMessage = "Please answer every required question before continuing."

    static func initialSelectedOptions(for input: ManagedAgentUserInputRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: input.questions.compactMap { question in
            question.options.first.map { (question.id, $0.label) }
        })
    }

    static func requestDescription(for kind: ManagedAgentInteractionKind) -> String {
        switch kind {
        case .commandApproval:
            return "The agent paused because the current approval policy requires explicit consent for this command."
        case .fileChangeApproval:
            return "The agent paused before writing files outside the current allowance."
        case .userInput:
            return "The agent needs a small bit of guidance before it can continue the turn."
        }
    }

    static func cancelResponse(for kind: ManagedAgentInteractionKind) -> ManagedAgentInteractionResponse {
        switch kind {
        case .commandApproval, .fileChangeApproval:
            return .approval(.cancel)
        case .userInput:
            return .cancelled(message: "User cancelled the interaction.")
        }
    }

    static func answers(
        for input: ManagedAgentUserInputRequest,
        textAnswers: [String: String],
        selectedOptions: [String: String]
    ) -> [String: [String]]? {
        var answers: [String: [String]] = [:]
        for question in input.questions {
            guard let value = textAnswers[question.id]?.trimmedNonEmpty
                ?? selectedOptions[question.id]?.trimmedNonEmpty else {
                return nil
            }

            answers[question.id] = [value]
        }

        return answers
    }
}
