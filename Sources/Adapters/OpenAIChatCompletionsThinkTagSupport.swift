import Foundation

/// Splits leading `<think>...</think>` blocks out of chat-completions content.
struct OpenAIChatCompletionsThinkTagSplitter {
    private static let startTag = "<think>"
    private static let endTag = "</think>"

    private var isInThinking = false
    private var hasEmittedVisibleNonWhitespace = false
    private var tagBuffer = ""

    mutating func process(_ input: String) -> (visible: String, thinking: String) {
        if tagBuffer.isEmpty, !input.contains("<") {
            if isInThinking {
                return (visible: "", thinking: input)
            }

            if !hasEmittedVisibleNonWhitespace,
               input.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil {
                hasEmittedVisibleNonWhitespace = true
            }
            return (visible: input, thinking: "")
        }

        var visibleOut = ""
        var thinkingOut = ""
        visibleOut.reserveCapacity(input.count)

        func appendLiteral(_ ch: Character) {
            if isInThinking {
                thinkingOut.append(ch)
            } else {
                visibleOut.append(ch)
                if !hasEmittedVisibleNonWhitespace,
                   String(ch).rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil {
                    hasEmittedVisibleNonWhitespace = true
                }
            }
        }

        func flushTagBufferAsLiteral() {
            guard !tagBuffer.isEmpty else { return }
            for ch in tagBuffer {
                appendLiteral(ch)
            }
            tagBuffer.removeAll(keepingCapacity: true)
        }

        func isPossibleTagPrefix(_ lower: String) -> Bool {
            Self.startTag.hasPrefix(lower) || Self.endTag.hasPrefix(lower)
        }

        for ch in input {
            if tagBuffer.isEmpty {
                if ch == "<" {
                    tagBuffer.append(ch)
                    continue
                }
                appendLiteral(ch)
                continue
            }

            tagBuffer.append(ch)
            let lower = tagBuffer.lowercased()

            if lower == Self.startTag {
                if !isInThinking, !hasEmittedVisibleNonWhitespace {
                    isInThinking = true
                    tagBuffer.removeAll(keepingCapacity: true)
                    continue
                }
                flushTagBufferAsLiteral()
                continue
            }

            if lower == Self.endTag {
                if isInThinking {
                    isInThinking = false
                    tagBuffer.removeAll(keepingCapacity: true)
                    continue
                }
                flushTagBufferAsLiteral()
                continue
            }

            if isPossibleTagPrefix(lower) {
                continue
            }

            while !tagBuffer.isEmpty {
                let currentLower = tagBuffer.lowercased()
                if isPossibleTagPrefix(currentLower) {
                    break
                }
                let first = tagBuffer.removeFirst()
                appendLiteral(first)
            }
        }

        return (visibleOut, thinkingOut)
    }

    mutating func flushRemainder() -> (visible: String, thinking: String) {
        guard !tagBuffer.isEmpty else { return ("", "") }
        let remainder = tagBuffer
        tagBuffer.removeAll(keepingCapacity: true)
        return isInThinking ? ("", remainder) : (remainder, "")
    }

    static func splitNonStreaming(_ input: String) -> (visible: String, thinking: String?) {
        guard input.lowercased().contains("<think>") else {
            return (input, nil)
        }

        var splitter = OpenAIChatCompletionsThinkTagSplitter()
        let first = splitter.process(input)
        let remainder = splitter.flushRemainder()
        let visible = first.visible + remainder.visible
        let thinkingRaw = first.thinking + remainder.thinking
        return (visible, thinkingRaw.isEmpty ? nil : thinkingRaw)
    }
}
