import Foundation

/// Anthropic requires every `tool_use` block to be followed immediately by a `tool_result` block
/// (in the next message). Jin stores tool results as `.tool` messages, which can be missing or
/// out of order (e.g. due to sorting or interrupted runs).
///
/// This normalizer rebuilds a safe message sequence for Anthropic requests by:
/// - Dropping existing `.tool` messages from the history.
/// - Re-inserting a synthetic `.tool` message immediately after each assistant message that
///   contains tool calls, populated from any recorded tool results (or a placeholder error).
enum AnthropicToolUseNormalizer {
    static func normalize(_ messages: [Message]) -> [Message] {
        guard !messages.isEmpty else { return [] }

        var resultsByToolUseID: [String: ToolResult] = [:]
        for message in messages {
            for result in message.toolResults ?? [] {
                // Prefer the latest occurrence.
                resultsByToolUseID[result.toolCallID] = result
            }
        }

        var normalized: [Message] = []
        normalized.reserveCapacity(messages.count + 4)

        for message in messages {
            switch message.role {
            case .tool:
                // Tool results are reinserted after the corresponding assistant tool_use message.
                continue

            case .assistant:
                // Anthropic thinking signatures are opaque and can cause hard failures if a stored
                // signature is truncated/foreign. Since thinking blocks are not user-visible content,
                // we omit them from request history and keep only visible content + tool_use/tool_result.
                let sanitizedContent = message.content.filter { part in
                    switch part {
                    case .thinking, .redactedThinking:
                        return false
                    default:
                        return true
                    }
                }

                normalized.append(
                    Message(
                        id: message.id,
                        role: .assistant,
                        content: sanitizedContent,
                        toolCalls: message.toolCalls,
                        toolResults: nil,
                        timestamp: message.timestamp
                    )
                )

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    let results: [ToolResult] = toolCalls.map { call in
                        if let existing = resultsByToolUseID[call.id] {
                            return existing
                        }
                        return ToolResult(
                            toolCallID: call.id,
                            toolName: call.name,
                            content: "Tool result missing (auto-generated).",
                            isError: true,
                            signature: call.signature
                        )
                    }

                    normalized.append(
                        Message(
                            role: .tool,
                            content: [],
                            toolResults: results
                        )
                    )
                }

            case .user:
                // Never send stray tool_results on user turns; only the synthetic `.tool` message
                // should carry tool_result blocks to satisfy Anthropic's ordering rules.
                normalized.append(
                    Message(
                        id: message.id,
                        role: .user,
                        content: message.content,
                        toolCalls: nil,
                        toolResults: nil,
                        timestamp: message.timestamp
                    )
                )

            case .system:
                normalized.append(
                    Message(
                        id: message.id,
                        role: .system,
                        content: message.content,
                        toolCalls: nil,
                        toolResults: nil,
                        timestamp: message.timestamp
                    )
                )
            }
        }

        return normalized
    }
}
