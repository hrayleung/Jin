import Foundation

extension ChatDropHandlingSupport {
    static func appendTextChunksToComposer(
        _ textChunks: [String],
        currentText: String
    ) -> String? {
        let insertion = textChunks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !insertion.isEmpty else { return nil }

        if currentText.isEmpty {
            return insertion
        } else {
            let separator = currentText.hasSuffix("\n") ? "" : "\n"
            return currentText + separator + insertion
        }
    }
}
