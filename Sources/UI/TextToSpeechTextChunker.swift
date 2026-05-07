import Foundation

enum TextToSpeechTextChunker {
    static func chunks(for text: String, maxCharacters: Int) -> [String] {
        guard let trimmed = text.trimmedNonEmpty else { return [] }
        guard maxCharacters > 0 else { return [trimmed] }
        guard trimmed.count > maxCharacters else { return [trimmed] }

        var result: [String] = []
        result.reserveCapacity(max(2, trimmed.count / maxCharacters))

        let paragraphs = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        var current = ""

        func flush() {
            if let out = current.trimmedNonEmpty {
                result.append(out)
            }
            current = ""
        }

        for paragraph in paragraphs {
            if paragraph.count > maxCharacters {
                flush()
                result.append(contentsOf: hardSplit(paragraph, maxCharacters: maxCharacters))
                continue
            }

            if current.isEmpty {
                current = paragraph
                continue
            }

            let candidate = current + "\n" + paragraph
            if candidate.count <= maxCharacters {
                current = candidate
            } else {
                flush()
                current = paragraph
            }
        }

        flush()
        return result
    }

    private static func hardSplit(_ text: String, maxCharacters: Int) -> [String] {
        guard maxCharacters > 0 else { return [text] }
        var out: [String] = []
        out.reserveCapacity(max(1, text.count / maxCharacters))

        var buffer = ""
        buffer.reserveCapacity(maxCharacters)

        for ch in text {
            buffer.append(ch)
            if buffer.count >= maxCharacters {
                out.append(buffer)
                buffer = ""
            }
        }

        if !buffer.isEmpty {
            out.append(buffer)
        }

        return out.compactMap(\.trimmedNonEmpty)
    }
}
