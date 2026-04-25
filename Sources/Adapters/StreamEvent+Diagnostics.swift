extension StreamEvent {
    var diagnosticName: String {
        switch self {
        case .messageStart:
            return "messageStart"
        case .contentDelta:
            return "contentDelta"
        case .thinkingDelta:
            return "thinkingDelta"
        case .toolCallStart:
            return "toolCallStart"
        case .toolCallDelta:
            return "toolCallDelta"
        case .toolCallEnd:
            return "toolCallEnd"
        case .searchActivity:
            return "searchActivity"
        case .codeExecutionActivity:
            return "codeExecutionActivity"
        case .codexToolActivity:
            return "codexToolActivity"
        case .codexInteractionRequest:
            return "codexInteractionRequest"
        case .codexThreadState:
            return "codexThreadState"
        case .claudeManagedSessionState:
            return "claudeManagedSessionState"
        case .claudeManagedCustomToolResults:
            return "claudeManagedCustomToolResults"
        case .messageEnd:
            return "messageEnd"
        case .error:
            return "error"
        }
    }
}
