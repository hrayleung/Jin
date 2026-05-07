import Foundation

extension ClaudeManagedAgentRequestSupport {
    static func approvalEvent(
        from interaction: CodexInteractionRequest,
        response: CodexInteractionResponse
    ) throws -> [String: Any] {
        guard let toolUseID = interaction.itemID else {
            throw LLMError.invalidRequest(
                message: "Claude Managed Agents approval reply is missing the required event identifier."
            )
        }

        let payload = try toolConfirmationPayload(from: response)
        var event: [String: Any] = [
            "type": "user.tool_confirmation",
            "tool_use_id": toolUseID,
            "result": payload.result
        ]
        if let denyMessage = payload.denyMessage {
            event["deny_message"] = denyMessage
        }
        return event
    }

    private struct ToolConfirmationPayload {
        let result: String
        let denyMessage: String?
    }

    private static func toolConfirmationPayload(from response: CodexInteractionResponse) throws -> ToolConfirmationPayload {
        switch response {
        case .approval(let choice):
            switch choice {
            case .accept, .acceptForSession:
                return ToolConfirmationPayload(result: "allow", denyMessage: nil)
            case .decline, .cancel:
                return ToolConfirmationPayload(result: "deny", denyMessage: nil)
            }
        case .cancelled(let message):
            return ToolConfirmationPayload(
                result: "deny",
                denyMessage: normalizedTrimmedString(message)
            )
        case .userInput:
            throw LLMError.invalidRequest(
                message: "Claude Managed Agents tool approval does not accept free-form user input."
            )
        }
    }
}
