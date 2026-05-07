import Foundation

enum MessageSelectionSupport {
    static func normalizedSelectedText(_ selectedText: String) -> String? {
        selectedText.trimmedNonEmpty
    }

    static func selectionIsEmpty(_ selectedText: String) -> Bool {
        normalizedSelectedText(selectedText) == nil
    }
}
