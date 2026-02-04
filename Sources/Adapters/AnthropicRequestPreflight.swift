import Foundation

/// Lightweight validation/sanitized debugging for Anthropic tool-use request invariants.
///
/// Anthropic requires:
/// - Each assistant `tool_use` turn must be followed immediately by a `user` message that contains
///   corresponding `tool_result` blocks.
/// - In that `user` message, `tool_result` blocks must come first in the `content` array.
enum AnthropicRequestPreflight {
    static func validate(messages: [[String: Any]]) throws {
        var problems: [String] = []

        for index in messages.indices {
            guard let role = messages[index]["role"] as? String, role == "assistant" else { continue }

            let toolUseIDs = toolUseIDs(in: contentBlocks(in: messages[index]))
            guard !toolUseIDs.isEmpty else { continue }

            guard messages.indices.contains(index + 1) else {
                problems.append("[messages.\(index)] assistant has tool_use ids \(formatIDs(toolUseIDs)) but there is no next message")
                continue
            }

            let next = messages[index + 1]
            let nextRole = next["role"] as? String ?? "<missing>"
            guard nextRole == "user" else {
                problems.append("[messages.\(index)] assistant tool_use ids \(formatIDs(toolUseIDs)) must be followed by role=user (found role=\(nextRole))")
                continue
            }

            let nextBlocks = contentBlocks(in: next)
            let toolResult = toolResultIDs(in: nextBlocks)

            if toolResult.outOfOrder {
                problems.append("[messages.\(index + 1)] tool_result blocks must come first in the user message content")
            }

            let missing = Set(toolUseIDs).subtracting(toolResult.prefix)
            if !missing.isEmpty {
                problems.append("[messages.\(index)] missing tool_result blocks immediately after tool_use ids \(formatIDs(Array(missing).sorted())) (next message has tool_result prefix ids \(formatIDs(toolResult.prefix)))")
            }
        }

        guard problems.isEmpty else {
            let detail = problems.prefix(10).joined(separator: "\n")
            throw LLMError.invalidRequest(
                message: """
Anthropic tool_use/tool_result ordering invalid:
\(detail)

Sanitized message summary:
\(summarize(messages: messages))
"""
            )
        }
    }

    // MARK: - Helpers

    private static func summarize(messages: [[String: Any]]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(messages.count)

        for index in messages.indices {
            let role = (messages[index]["role"] as? String) ?? "<missing>"
            let blocks = contentBlocks(in: messages[index])
            let types = blocks.compactMap { $0["type"] as? String }

            let toolUseIDs = toolUseIDs(in: blocks)
            let toolResult = toolResultIDs(in: blocks)

            var suffix: [String] = []
            if !toolUseIDs.isEmpty {
                suffix.append("tool_use=\(formatIDs(toolUseIDs))")
            }
            if !toolResult.prefix.isEmpty || !toolResult.all.isEmpty {
                suffix.append("tool_result_prefix=\(formatIDs(toolResult.prefix))")
            }

            let typesText = types.isEmpty ? "<no_blocks>" : types.joined(separator: ",")
            if suffix.isEmpty {
                lines.append("[\(index)] \(role): \(typesText)")
            } else {
                lines.append("[\(index)] \(role): \(typesText) (\(suffix.joined(separator: " ")))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func contentBlocks(in message: [String: Any]) -> [[String: Any]] {
        if let blocks = message["content"] as? [[String: Any]] { return blocks }
        return []
    }

    private static func toolUseIDs(in blocks: [[String: Any]]) -> [String] {
        var ids: [String] = []
        ids.reserveCapacity(2)

        for block in blocks {
            guard (block["type"] as? String) == "tool_use" else { continue }
            if let id = block["id"] as? String {
                ids.append(id)
            }
        }

        return ids
    }

    private static func toolResultIDs(in blocks: [[String: Any]]) -> (prefix: [String], all: [String], outOfOrder: Bool) {
        var prefix: [String] = []
        var all: [String] = []
        var outOfOrder = false

        var stillInPrefix = true

        for block in blocks {
            let type = block["type"] as? String
            if type == "tool_result" {
                let id = (block["tool_use_id"] as? String) ?? "<missing>"
                all.append(id)
                if stillInPrefix {
                    prefix.append(id)
                } else {
                    outOfOrder = true
                }
            } else {
                stillInPrefix = false
            }
        }

        return (prefix: prefix, all: all, outOfOrder: outOfOrder)
    }

    private static func formatIDs(_ ids: [String], limit: Int = 3) -> String {
        guard !ids.isEmpty else { return "[]" }
        if ids.count <= limit { return "[" + ids.joined(separator: ", ") + "]" }
        return "[" + ids.prefix(limit).joined(separator: ", ") + ", …+\(ids.count - limit)]"
    }
}

