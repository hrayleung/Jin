import Foundation

// MARK: - Search Activity Parsing

extension CodexAppServerAdapter {

    nonisolated static func searchActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> SearchActivity? {
        let itemType = item.string(at: ["type"]) ?? ""
        if itemType == "webSearch" {
            return searchActivityFromWebSearchItem(item: item, method: method)
        }
        if itemType == "dynamicToolCall" {
            return searchActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }
        return nil
    }
}
