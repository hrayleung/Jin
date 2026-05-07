import Foundation

enum XAIMediaPromptSupport {
    enum EditMode {
        case none
        case image
        case video
    }

    static func prompt(from messages: [Message], mode: EditMode) throws -> String {
        let userPrompts = userTextPrompts(from: messages)
        guard let latest = userPrompts.last else {
            throw LLMError.invalidRequest(message: "xAI media generation requires a text prompt.")
        }

        guard mode != .none else {
            return latest
        }

        let recentPrompts = Array(userPrompts.suffix(6))
        let originalPrompt = recentPrompts.first ?? latest
        let latestPrompt = recentPrompts.last ?? latest
        let priorEdits = Array(recentPrompts.dropFirst().dropLast())

        if mode == .image, userPrompts.count < 2 {
            return latest
        }

        if mode == .image,
           priorEdits.isEmpty,
           originalPrompt.caseInsensitiveCompare(latestPrompt) == .orderedSame {
            return latest
        }

        let continuityInstruction: String = switch mode {
        case .image:
            "Keep the main subject, composition, and scene continuity unless explicitly changed."
        case .video:
            "Keep the main subject, composition, camera motion, and timing continuity unless explicitly changed."
        case .none:
            ""
        }

        let mediaLabel: String = switch mode {
        case .image: "image"
        case .video: "video"
        case .none: "media"
        }

        var lines: [String] = [
            "Edit the provided input \(mediaLabel).",
            continuityInstruction,
            "",
            "Original request:",
            originalPrompt
        ]

        if !priorEdits.isEmpty {
            lines.append("")
            lines.append("Edits already applied:")
            for (idx, edit) in priorEdits.enumerated() {
                lines.append("\(idx + 1). \(edit)")
            }
        }

        lines.append("")
        lines.append("Apply this new edit now:")
        lines.append(latestPrompt)

        return lines.joined(separator: "\n")
    }

    static func userTextPrompts(from messages: [Message]) -> [String] {
        messages.compactMap { message in
            guard message.role == .user else { return nil }

            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                return normalizedTrimmedString(value)
            }
            .joined(separator: "\n\n")

            return normalizedTrimmedString(text)
        }
    }
}
