import Foundation

extension CodexAppServerAdapter {
    nonisolated static func parseAgentMessageText(from item: [String: JSONValue]) -> String? {
        let root = JSONValue.object(item)
        let collected = collectAgentMessageTextFragments(from: root)
            .joined()
        return trimmedValue(collected)
    }

    nonisolated static func assistantTextSuffix(fromSnapshot snapshot: String, emitted: String) -> String? {
        guard !snapshot.isEmpty else { return nil }
        if emitted.isEmpty {
            return snapshot
        }
        if snapshot == emitted {
            return nil
        }
        if snapshot.hasPrefix(emitted) {
            let index = snapshot.index(snapshot.startIndex, offsetBy: emitted.count)
            let suffix = String(snapshot[index...])
            return suffix.isEmpty ? nil : suffix
        }
        if trimmedValue(emitted) == nil {
            return snapshot
        }
        return nil
    }

    nonisolated static func collectAgentMessageTextFragments(from value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            return [text]

        case .array(let array):
            return array.flatMap { collectAgentMessageTextFragments(from: $0) }

        case .object(let object):
            var fragments: [String] = []

            if let text = object.string(at: ["text"]) {
                fragments.append(text)
            }
            if let valueText = object.string(at: ["value"]),
               object.string(at: ["type"]) == "output_text" || object.string(at: ["type"]) == "text" {
                fragments.append(valueText)
            }

            for key in ["message", "content", "contentItems", "output", "parts", "item"] {
                guard let nested = object[key] else { continue }
                fragments.append(contentsOf: collectAgentMessageTextFragments(from: nested))
            }
            return fragments

        default:
            return []
        }
    }

    nonisolated static func parseDynamicToolCallOutputParts(
        from item: [String: JSONValue]
    ) -> [ContentPart] {
        guard let contentItems = item.array(at: ["contentItems"]), !contentItems.isEmpty else {
            return []
        }

        var parts: [ContentPart] = []
        parts.reserveCapacity(contentItems.count)

        for contentItem in contentItems {
            guard let object = contentItem.objectValue else { continue }
            let type = object.string(at: ["type"])?.lowercased()
            switch type {
            case "inputtext", "input_text":
                if let text = trimmedValue(object.string(at: ["text"])) {
                    parts.append(.text(text))
                }
            case "inputimage", "input_image":
                let rawURL = trimmedValue(object.string(at: ["imageUrl"]) ?? object.string(at: ["image_url"]))
                if let rawURL, let url = URL(string: rawURL) {
                    parts.append(.image(ImageContent(mimeType: "image/png", url: url, assetDisposition: .externalReference)))
                }
            default:
                break
            }
        }

        return parts
    }
}
