import Foundation

enum ToolSearchActivityFactory {

    static func normalizedToolResultContent(
        _ text: String,
        toolName: String,
        isError: Bool
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if isError {
            return "Tool \(toolName) failed without details"
        }
        return "Tool \(toolName) returned no output"
    }

    static func activityForToolCallStart(
        call: ToolCall,
        providerOverride: SearchPluginProvider?
    ) -> SearchActivity? {
        guard isSearchToolName(call.name) else { return nil }

        var args: [String: AnyCodable] = [:]
        let query = (call.arguments["query"]?.value as? String)
            ?? (call.arguments["q"]?.value as? String)
            ?? ""
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            args["query"] = AnyCodable(trimmedQuery)
        }

        if let providerOverride {
            args["provider"] = AnyCodable(providerOverride.rawValue)
        }

        return SearchActivity(
            id: "tool-search-\(call.id)",
            type: "tool_web_search",
            status: .searching,
            arguments: args
        )
    }

    static func activityFromToolResult(
        call: ToolCall,
        toolResultText: String,
        isError: Bool,
        providerOverride: SearchPluginProvider?
    ) -> SearchActivity? {
        guard isSearchToolName(call.name) else { return nil }

        let decoder = JSONDecoder()
        var query = ""
        var sources: [[String: Any]] = []
        var providerRaw = providerOverride?.rawValue

        if let data = toolResultText.data(using: .utf8),
           let payload = try? decoder.decode(Payload.self, from: data) {
            query = payload.query
            providerRaw = providerRaw ?? payload.provider.rawValue
            sources = payload.results.map { row in
                var item: [String: Any] = [
                    "url": row.url,
                    "title": row.title,
                ]
                if let snippet = row.snippet {
                    item["snippet"] = snippet
                }
                if let publishedAt = row.publishedAt {
                    item["published_at"] = publishedAt
                }
                if let source = row.source {
                    item["source"] = source
                }
                return item
            }
        } else {
            query = (call.arguments["query"]?.value as? String)
                ?? (call.arguments["q"]?.value as? String)
                ?? ""
        }

        var args: [String: AnyCodable] = [:]
        if !query.isEmpty {
            args["query"] = AnyCodable(query)
        }
        if !sources.isEmpty {
            args["sources"] = AnyCodable(sources)
        }
        if let providerRaw, !providerRaw.isEmpty {
            args["provider"] = AnyCodable(providerRaw)
        }

        return SearchActivity(
            id: "tool-search-\(call.id)",
            type: "tool_web_search",
            status: isError ? .failed : .completed,
            arguments: args
        )
    }

    static func isSearchToolName(_ toolName: String) -> Bool {
        let normalizedName = toolName.lowercased()
        return normalizedName.contains("search")
            || normalizedName.contains("web_lookup")
            || normalizedName.contains("web_search")
    }
}

// MARK: - Payload Types

extension ToolSearchActivityFactory {

    struct Payload: Decodable {
        let provider: SearchPluginProvider
        let query: String
        let results: [PayloadRow]
    }

    struct PayloadRow: Decodable {
        let title: String
        let url: String
        let snippet: String?
        let publishedAt: String?
        let source: String?
    }
}
