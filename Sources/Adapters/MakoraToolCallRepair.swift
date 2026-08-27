import Foundation

/// Client-side repair for Makora vLLM builds that emit tool calls as raw text
/// instead of OpenAI `delta.tool_calls` (documented by omp-makora-provider).
enum MakoraToolCallRepair {
    struct ParsedCall: Equatable {
        let name: String
        let argumentsJSON: String
    }

    static func parse(_ text: String, modelID: String) -> [ParsedCall] {
        let canonical = MakoraModelSupport.canonicalModelID(for: modelID)
        switch canonical.lowercased() {
        case MakoraModelSupport.glm51ID.lowercased():
            return parseGLMToolCalls(text)
        case MakoraModelSupport.kimiK26ID.lowercased(),
             MakoraModelSupport.kimiK27ID.lowercased():
            return parseKimiToolCalls(text)
        case MakoraModelSupport.qwen27BID.lowercased(),
             MakoraModelSupport.qwen35BID.lowercased():
            return parseQwenToolCalls(text)
        default:
            return []
        }
    }

    static func textBeforeTools(_ text: String, modelID: String) -> String {
        let canonical = MakoraModelSupport.canonicalModelID(for: modelID)
        switch canonical.lowercased() {
        case MakoraModelSupport.glm51ID.lowercased():
            if let idx = text.range(of: "<tool_call>") {
                return String(text[..<idx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case MakoraModelSupport.kimiK26ID.lowercased(),
             MakoraModelSupport.kimiK27ID.lowercased():
            if let idx = text.range(of: "<|tool_call_begin|>") {
                return String(text[..<idx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case MakoraModelSupport.qwen27BID.lowercased(),
             MakoraModelSupport.qwen35BID.lowercased():
            let cleaned = text.replacingOccurrences(of: "█", with: "")
            if let idx = cleaned.range(of: "<function=") {
                return String(cleaned[..<idx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return text
        default:
            break
        }
        return text
    }

    static func glmXML(from toolCalls: [ToolCall], preceding: String) -> String {
        let xml = toolCalls.map { call in
            let args = encodeJSONObject(call.arguments)
            return "<tool_call>\n<tool_name>\(call.name)</tool_name>\n<parameters>\(args)</parameters>\n</tool_call>"
        }.joined(separator: "\n")
        if preceding.trimmed.isEmpty {
            return xml
        }
        return "\(preceding)\n\(xml)"
    }

    static func toolCalls(from parsed: [ParsedCall]) -> [ToolCall] {
        parsed.map { call in
            let arguments: [String: AnyCodable]
            if let data = call.argumentsJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                arguments = object.mapValues { AnyCodable($0) }
            } else {
                arguments = [:]
            }
            return ToolCall(
                id: "call_\(UUID().uuidString)",
                name: call.name,
                arguments: arguments
            )
        }
    }

    // MARK: - Parsers

    private static func parseGLMToolCalls(_ text: String) -> [ParsedCall] {
        parseMatches(
            in: text,
            pattern: #"<tool_call>\s*<tool_name>([^<]+)</tool_name>\s*<parameters>([\s\S]*?)</parameters>\s*</tool_call>"#
        )
    }

    private static func parseKimiToolCalls(_ text: String) -> [ParsedCall] {
        parseMatches(
            in: text,
            pattern: #"<\|tool_call_begin\|>([^\n]+)\n([\s\S]*?)<\|tool_call_end\|>"#
        )
    }

    private static func parseQwenToolCalls(_ text: String) -> [ParsedCall] {
        let cleaned = text.replacingOccurrences(of: "█", with: "")
        return parseMatches(
            in: cleaned,
            pattern: #"<function=([^>]+)>([\s\S]*?)</function>"#
        )
    }

    private static func parseMatches(in text: String, pattern: String) -> [ParsedCall] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawArgs = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, isJSONObject(rawArgs) else { return nil }
            return ParsedCall(name: name, argumentsJSON: rawArgs)
        }
    }

    private static func isJSONObject(_ raw: String) -> Bool {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return object is [String: Any]
    }
}
