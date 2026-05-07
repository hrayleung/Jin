import Foundation

struct ComposerDraftTextMetrics: Equatable {
    let wordCount: Int
    let characterCount: Int

    init(messageText: String) {
        characterCount = messageText.count

        guard let trimmed = messageText.trimmedNonEmpty else {
            wordCount = 0
            return
        }

        wordCount = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var summaryText: String {
        guard characterCount > 0 else { return "0 words · 0 characters" }

        let wordLabel = wordCount == 1 ? "1 word" : "\(wordCount) words"
        let characterLabel = characterCount == 1 ? "1 character" : "\(characterCount) characters"
        return "\(wordLabel) · \(characterLabel)"
    }
}
