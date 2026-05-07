import Collections
import Foundation

extension CodexAppServerAdapter {
    nonisolated static func searchActivityFromWebSearchItem(
        item: [String: JSONValue],
        method: String
    ) -> SearchActivity? {
        guard item.string(at: ["type"]) == "webSearch" else { return nil }
        let id = trimmedValue(item.string(at: ["id"])) ?? UUID().uuidString

        var arguments: [String: AnyCodable] = [:]
        var queriesByKey: OrderedDictionary<String, String> = [:]

        func appendQuery(_ raw: String?) {
            guard let query = trimmedValue(raw) else { return }
            let key = query.lowercased()
            guard queriesByKey[key] == nil else { return }
            queriesByKey[key] = query
        }

        appendQuery(item.string(at: ["query"]))
        if let action = item.object(at: ["action"]) {
            appendQuery(action.string(at: ["query"]))
            for queryValue in action.array(at: ["queries"]) ?? [] {
                appendQuery(queryValue.stringValue)
            }
            if let url = trimmedValue(action.string(at: ["url"])) {
                arguments["url"] = AnyCodable(url)
            }
            if let pattern = trimmedValue(action.string(at: ["pattern"])) {
                arguments["pattern"] = AnyCodable(pattern)
            }
            if let actionType = trimmedValue(action.string(at: ["type"])) {
                arguments["action_type"] = AnyCodable(actionType)
            }
        }

        let queryList = Array(queriesByKey.values)
        if let firstQuery = queryList.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queryList)
        }

        let status: SearchActivityStatus
        if method == "item/completed" || method.hasSuffix("/completed") {
            status = .completed
        } else if method.hasSuffix("/failed") {
            status = .failed
        } else {
            status = .searching
        }

        return SearchActivity(
            id: id,
            type: "web_search_call",
            status: status,
            arguments: arguments
        )
    }
}
