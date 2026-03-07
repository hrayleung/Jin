import Foundation

struct CodexAppServerRequestBuilder {
    static let defaultApprovalPolicy = "never"

    static func threadStartParams(modelID: String, controls: GenerationControls) -> [String: Any] {
        var params: [String: Any] = [
            "model": modelID,
            "approvalPolicy": defaultApprovalPolicy,
            "sandbox": controls.codexSandboxMode.threadStartValue,
            "experimentalRawEvents": false,
            "persistExtendedHistory": false
        ]

        if let cwd = controls.codexWorkingDirectory {
            params["cwd"] = cwd
        }
        if let personality = controls.codexPersonality {
            params["personality"] = personality.rawValue
        }
        if let baseInstructions = providerString(key: "codex_base_instructions", controls: controls) {
            params["baseInstructions"] = baseInstructions
        }
        if let developerInstructions = providerString(key: "codex_developer_instructions", controls: controls) {
            params["developerInstructions"] = developerInstructions
        }

        return params
    }

    static func threadResumeParams(threadID: String, modelID: String, controls: GenerationControls) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "model": modelID,
            "approvalPolicy": defaultApprovalPolicy,
            "sandbox": controls.codexSandboxMode.threadStartValue,
            "persistExtendedHistory": false
        ]

        if let cwd = controls.codexWorkingDirectory {
            params["cwd"] = cwd
        }
        if let personality = controls.codexPersonality {
            params["personality"] = personality.rawValue
        }
        if let baseInstructions = providerString(key: "codex_base_instructions", controls: controls) {
            params["baseInstructions"] = baseInstructions
        }
        if let developerInstructions = providerString(key: "codex_developer_instructions", controls: controls) {
            params["developerInstructions"] = developerInstructions
        }

        return params
    }

    static func turnStartParams(
        threadID: String,
        inputItems: [Any],
        modelID: String,
        controls: GenerationControls
    ) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "approvalPolicy": defaultApprovalPolicy,
            "input": inputItems,
            "model": modelID,
            "sandboxPolicy": controls.codexSandboxMode.turnStartValue
        ]

        if let cwd = controls.codexWorkingDirectory {
            params["cwd"] = cwd
        }
        if let personality = controls.codexPersonality {
            params["personality"] = personality.rawValue
        }
        if let schema = providerSpecificValue(key: "codex_output_schema", controls: controls)
            ?? providerSpecificValue(key: "output_schema", controls: controls) {
            params["outputSchema"] = schema
        }

        if let reasoning = controls.reasoning, reasoning.enabled {
            let effort = reasoning.effort ?? .medium
            params["effort"] = effort.rawValue
            if let summary = reasoning.summary {
                params["summary"] = summary.rawValue
            }
        }

        return params
    }

    private static func providerSpecificValue(key: String, controls: GenerationControls) -> Any? {
        controls.providerSpecific[key]?.value
    }

    private static func providerString(key: String, controls: GenerationControls) -> String? {
        guard let value = providerSpecificValue(key: key, controls: controls) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CodexAppServerAutoReply {
    static func result(forServerRequestMethod method: String) -> [String: Any]? {
        switch method {
        case "item/commandExecution/requestApproval":
            return ["decision": "decline"]
        case "item/fileChange/requestApproval":
            return ["decision": "decline"]
        case "applyPatchApproval":
            return ["decision": "denied"]
        case "execCommandApproval":
            return ["decision": "denied"]
        default:
            return nil
        }
    }
}
