import Foundation

extension CodexAppServerAdapter {
    nonisolated static func interactionRequest(
        id _: JSONRPCID,
        method: String,
        params: [String: JSONValue]
    ) -> CodexInteractionRequest? {
        switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval":
            guard let request = parseCommandApprovalRequest(method: method, params: params) else { return nil }
            return CodexInteractionRequest(
                method: method,
                threadID: params.string(at: ["threadId"]) ?? params.string(at: ["conversationId"]),
                turnID: params.string(at: ["turnId"]),
                itemID: params.string(at: ["itemId"]) ?? params.string(at: ["callId"]),
                kind: .commandApproval(request)
            )
        case "item/fileChange/requestApproval", "applyPatchApproval":
            guard let request = parseFileChangeApprovalRequest(method: method, params: params) else { return nil }
            return CodexInteractionRequest(
                method: method,
                threadID: params.string(at: ["threadId"]) ?? params.string(at: ["conversationId"]),
                turnID: params.string(at: ["turnId"]),
                itemID: params.string(at: ["itemId"]) ?? params.string(at: ["callId"]),
                kind: .fileChangeApproval(request)
            )
        case "item/tool/requestUserInput":
            guard let request = parseUserInputRequest(params: params) else { return nil }
            return CodexInteractionRequest(
                method: method,
                threadID: params.string(at: ["threadId"]),
                turnID: params.string(at: ["turnId"]),
                itemID: params.string(at: ["itemId"]),
                kind: .userInput(request)
            )
        default:
            return nil
        }
    }

    nonisolated static func sendInteractionResponse(
        _ response: CodexInteractionResponse,
        for request: CodexInteractionRequest,
        requestID: JSONRPCID,
        client: CodexWebSocketRPCClient
    ) async throws {
        switch response {
        case .approval(let choice):
            try await client.respond(
                id: requestID,
                result: approvalResultPayload(for: request.method, choice: choice)
            )
        case .userInput(let answers):
            let payload = [
                "answers": answers.mapValues { values in
                    ["answers": values]
                }
            ]
            try await client.respond(id: requestID, result: payload)
        case .cancelled(let message):
            switch request.kind {
            case .commandApproval, .fileChangeApproval:
                try await client.respond(
                    id: requestID,
                    result: approvalResultPayload(for: request.method, choice: .cancel)
                )
            case .userInput:
                try await client.respondWithError(
                    id: requestID,
                    code: -32000,
                    message: message ?? "User cancelled the Codex interaction request."
                )
            }
        }
    }

    private nonisolated static func approvalResultPayload(for method: String, choice: CodexApprovalChoice) -> [String: Any] {
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            let value: String
            switch choice {
            case .accept:
                value = "accept"
            case .acceptForSession:
                value = "acceptForSession"
            case .decline:
                value = "decline"
            case .cancel:
                value = "cancel"
            }
            return ["decision": value]
        case "execCommandApproval", "applyPatchApproval":
            let value: String
            switch choice {
            case .accept:
                value = "approved"
            case .acceptForSession:
                value = "approved_for_session"
            case .decline:
                value = "denied"
            case .cancel:
                value = "abort"
            }
            return ["decision": value]
        default:
            return ["decision": "decline"]
        }
    }

    private nonisolated static func parseCommandApprovalRequest(
        method: String,
        params: [String: JSONValue]
    ) -> CodexCommandApprovalRequest? {
        let command: String?
        if let direct = trimmedValue(params.string(at: ["command"])) {
            command = direct
        } else if let argv = params.array(at: ["command"]), !argv.isEmpty {
            command = CommandLineTokenizer.render(argv.compactMap(\.stringValue))
        } else {
            command = nil
        }

        let actionSource = params.array(at: [method == "execCommandApproval" ? "parsedCmd" : "commandActions"]) ?? []
        let actionSummaries = actionSource.compactMap { actionValue -> CodexCommandActionSummary? in
            guard let action = actionValue.objectValue else { return nil }
            let type = action.string(at: ["type"])?.lowercased() ?? "unknown"
            let commandText = trimmedValue(action.string(at: ["command"]) ?? action.string(at: ["cmd"]))
            let path = trimmedValue(action.string(at: ["path"]))
            let name = trimmedValue(action.string(at: ["name"]))
            let query = trimmedValue(action.string(at: ["query"]))

            switch type {
            case "read":
                return CodexCommandActionSummary(
                    title: name ?? "Read file",
                    subtitle: path ?? commandText
                )
            case "listfiles", "list_files":
                return CodexCommandActionSummary(
                    title: "List files",
                    subtitle: path ?? commandText
                )
            case "search":
                var details: [String] = []
                if let query { details.append(query) }
                if let path { details.append(path) }
                return CodexCommandActionSummary(
                    title: "Search workspace",
                    subtitle: details.isEmpty ? commandText : details.joined(separator: " · ")
                )
            default:
                return CodexCommandActionSummary(
                    title: "Command step",
                    subtitle: commandText ?? path
                )
            }
        }

        return CodexCommandApprovalRequest(
            command: command,
            cwd: trimmedValue(params.string(at: ["cwd"])),
            reason: trimmedValue(params.string(at: ["reason"])),
            actionSummaries: actionSummaries
        )
    }

    private nonisolated static func parseFileChangeApprovalRequest(
        method: String,
        params: [String: JSONValue]
    ) -> CodexFileChangeApprovalRequest? {
        let fileChanges: [CodexFileChangeSummary]
        if method == "applyPatchApproval", let changes = params.object(at: ["fileChanges"]) {
            fileChanges = changes.keys.sorted().map { path in
                let type = changes[path]?.objectValue?.string(at: ["type"]) ?? "update"
                return CodexFileChangeSummary(path: path, changeType: humanReadableFileChangeType(type))
            }
        } else if let grantRoot = trimmedValue(params.string(at: ["grantRoot"])) {
            fileChanges = [CodexFileChangeSummary(path: grantRoot, changeType: "grant access")]
        } else {
            fileChanges = []
        }

        return CodexFileChangeApprovalRequest(
            reason: trimmedValue(params.string(at: ["reason"])),
            grantRoot: trimmedValue(params.string(at: ["grantRoot"])),
            fileChanges: fileChanges
        )
    }

    private nonisolated static func parseUserInputRequest(
        params: [String: JSONValue]
    ) -> CodexUserInputRequest? {
        guard let questionValues = params.array(at: ["questions"]), !questionValues.isEmpty else {
            return nil
        }

        let questions = questionValues.compactMap { questionValue -> CodexUserInputQuestion? in
            guard let question = questionValue.objectValue,
                  let id = trimmedValue(question.string(at: ["id"])),
                  let header = trimmedValue(question.string(at: ["header"])),
                  let prompt = trimmedValue(question.string(at: ["question"])) else {
                return nil
            }

            let options = (question.array(at: ["options"]) ?? []).compactMap { optionValue -> CodexUserInputOption? in
                guard let option = optionValue.objectValue,
                      let label = trimmedValue(option.string(at: ["label"])),
                      let detail = trimmedValue(option.string(at: ["description"])) else {
                    return nil
                }
                return CodexUserInputOption(label: label, detail: detail)
            }

            return CodexUserInputQuestion(
                id: id,
                header: header,
                prompt: prompt,
                isOtherAllowed: question.bool(at: ["isOther"]) ?? false,
                isSecret: question.bool(at: ["isSecret"]) ?? false,
                options: options
            )
        }

        return questions.isEmpty ? nil : CodexUserInputRequest(questions: questions)
    }

    private nonisolated static func humanReadableFileChangeType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "add":
            return "add"
        case "delete":
            return "delete"
        case "update":
            return "update"
        default:
            return raw
        }
    }
}
