import CoreGraphics
import Foundation

enum MarkdownWebRendererCoordinatorSupport {
    static let maximumContentHeight: CGFloat = 200_000

    struct SelectionContext: Equatable {
        let messageID: UUID?
        let anchorID: String?

        var javascript: String {
            let messageID = escapedJavaScriptSingleQuotedString(messageID?.uuidString ?? "")
            let anchorID = escapedJavaScriptSingleQuotedString(anchorID ?? "")
            return "window.setSelectionContext('\(messageID)', '', '\(anchorID)')"
        }
    }

    static func clampedHeight(
        from body: Any,
        maximumHeight: CGFloat = maximumContentHeight
    ) -> CGFloat? {
        guard let height = body as? CGFloat, height.isFinite else { return nil }
        return min(max(height, 1), maximumHeight)
    }

    static func persistedHighlightsPayload(
        _ persistedHighlights: [MessageHighlightSnapshot],
        selectionAnchorID: String?
    ) throws -> String {
        let highlightsForAnchor: [MessageHighlightSnapshot]
        if let selectionAnchorID {
            highlightsForAnchor = persistedHighlights.filter { $0.anchorID == selectionAnchorID }
        } else {
            highlightsForAnchor = []
        }

        let data = try JSONEncoder().encode(highlightsForAnchor)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw PayloadError.invalidUTF8
        }
        return payload
    }

    static func decodeSelectionSnapshot(_ body: Any) -> MessageSelectionSnapshot? {
        guard let dict = body as? [String: Any],
              let messageIDRaw = dict["messageID"] as? String,
              let messageID = UUID(uuidString: messageIDRaw),
              let anchorID = dict["anchorID"] as? String,
              let selectedText = dict["selectedText"] as? String else {
            return nil
        }

        let startOffset = (dict["startOffset"] as? NSNumber)?.intValue ?? 0
        let endOffset = (dict["endOffset"] as? NSNumber)?.intValue ?? 0
        let matchingHighlightIDs = (dict["matchingHighlightIDs"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))

        return MessageSelectionSnapshot(
            messageID: messageID,
            anchorID: anchorID,
            selectedText: selectedText,
            prefixContext: dict["prefixContext"] as? String,
            suffixContext: dict["suffixContext"] as? String,
            startOffset: startOffset,
            endOffset: endOffset,
            matchingHighlightIDs: matchingHighlightIDs
        )
    }

    private static func escapedJavaScriptSingleQuotedString(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }

    enum PayloadError: Error {
        case invalidUTF8
    }
}
