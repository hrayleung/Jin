import Foundation

extension GeminiModelConstants {
    struct GoogleCodeExecutionEventState {
        fileprivate var nextOrdinal = 0
        fileprivate var activeExecutionID: String?
        fileprivate var currentExecutionHasResult = false

        init() {}

        fileprivate mutating func executionIDForCodePart() -> String {
            if activeExecutionID == nil || currentExecutionHasResult {
                activeExecutionID = "google-code-execution-\(nextOrdinal)"
                nextOrdinal += 1
                currentExecutionHasResult = false
            }

            return activeExecutionID ?? "google-code-execution-unknown"
        }

        fileprivate mutating func executionIDForResultPart() -> String {
            if activeExecutionID == nil {
                activeExecutionID = "google-code-execution-\(nextOrdinal)"
                nextOrdinal += 1
            }
            currentExecutionHasResult = true
            return activeExecutionID ?? "google-code-execution-unknown"
        }
    }

    /// Converts a single Google `Part` response into domain `StreamEvent`s.
    /// Shared by both GeminiAdapter and VertexAIAdapter stream parsing.
    static func events(from part: GoogleGenerateContentResponse.Part) -> [StreamEvent] {
        var codeExecutionState = GoogleCodeExecutionEventState()
        return events(from: [part], codeExecutionState: &codeExecutionState)
    }

    static func events(
        from parts: [GoogleGenerateContentResponse.Part],
        codeExecutionState: inout GoogleCodeExecutionEventState
    ) -> [StreamEvent] {
        var out: [StreamEvent] = []

        for part in parts {
            out.append(contentsOf: events(from: part, codeExecutionState: &codeExecutionState))
        }

        return out
    }

    private static func events(
        from part: GoogleGenerateContentResponse.Part,
        codeExecutionState: inout GoogleCodeExecutionEventState
    ) -> [StreamEvent] {
        var out: [StreamEvent] = []

        if part.thought == true {
            let text = part.text ?? ""
            let signature = part.thoughtSignature
            if !text.isEmpty || signature != nil {
                out.append(.thinkingDelta(.thinking(textDelta: text, signature: signature)))
            }
        } else if let text = part.text, !text.isEmpty {
            out.append(.contentDelta(.text(text)))
        }

        if let inline = part.inlineData,
           let base64 = inline.data,
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
            let mimeType = inline.mimeType ?? "image/png"
            if mimeType.lowercased().hasPrefix("image/") {
                out.append(.contentDelta(.image(ImageContent(mimeType: mimeType, data: data))))
            }
        }

        if let executableCode = part.executableCode,
           let code = normalizedGoogleCodeExecutionText(executableCode.code) {
            let id = codeExecutionState.executionIDForCodePart()
            out.append(.codeExecutionActivity(CodeExecutionActivity(
                id: id,
                status: .writingCode,
                code: code
            )))
        }

        if let result = part.codeExecutionResult {
            let id = codeExecutionState.executionIDForResultPart()
            let status = googleCodeExecutionStatus(for: result.outcome)
            let output = normalizedGoogleCodeExecutionText(result.output)

            let activity: CodeExecutionActivity
            switch status {
            case .failed:
                activity = CodeExecutionActivity(
                    id: id,
                    status: status,
                    stderr: output
                )
            default:
                activity = CodeExecutionActivity(
                    id: id,
                    status: status,
                    stdout: output
                )
            }

            out.append(.codeExecutionActivity(activity))
        }

        if let functionCall = part.functionCall,
           !isGoogleProviderNativeToolName(functionCall.name) {
            let toolCall = ToolCall(
                id: UUID().uuidString,
                name: functionCall.name,
                arguments: functionCall.args ?? [:],
                signature: part.thoughtSignature
            )
            out.append(.toolCallStart(toolCall))
            out.append(.toolCallEnd(toolCall))
        }

        return out
    }

    private static func normalizedGoogleCodeExecutionText(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.isEmpty ? nil : normalized
    }

    private static func googleCodeExecutionStatus(for outcome: String?) -> CodeExecutionStatus {
        let normalized = (outcome ?? "OUTCOME_OK").uppercased()

        switch normalized {
        case "OUTCOME_OK", "OK", "SUCCESS":
            return .completed
        case "OUTCOME_FAILED", "FAILED", "ERROR":
            return .failed
        case "OUTCOME_DEADLINE_EXCEEDED", "DEADLINE_EXCEEDED", "TIMEOUT", "OUTCOME_CANCELLED", "CANCELLED":
            return .incomplete
        default:
            return .unknown(normalized.lowercased())
        }
    }
}
