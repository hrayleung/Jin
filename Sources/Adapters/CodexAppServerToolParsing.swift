import Foundation

// MARK: - Codex Tool Activity Parsing

extension CodexAppServerAdapter {

    nonisolated static func codexToolActivityFromDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        guard let toolName = dynamicToolCallName(from: item) else {
            return nil
        }
        guard !isLikelyWebSearchTool(named: toolName) else {
            return nil
        }

        let id = codexToolActivityID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = codexToolActivityArguments(from: item)
        let output = codexToolActivityOutput(from: item)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    nonisolated static func codexToolActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let itemType = item.string(at: ["type"]) ?? ""

        let nonToolTypes: Set<String> = [
            "webSearch",
            "agentMessage",
            "reasoning",
            "enteredReviewMode",
            "exitedReviewMode",
            "contextCompaction",
            "",
        ]
        if nonToolTypes.contains(itemType) {
            return nil
        }

        if itemType == "dynamicToolCall" {
            return codexToolActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }

        return codexToolActivityFromGenericItem(
            item: item,
            itemType: itemType,
            method: method,
            params: params,
            fallbackTurnID: fallbackTurnID
        )
    }

}
