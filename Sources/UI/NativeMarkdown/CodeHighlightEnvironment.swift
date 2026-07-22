import SwiftUI

private struct MarkdownDefersCodeHighlightUpgradeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Older offscreen/nearby timeline rows use the fast native tokenizer and
    /// skip the heavier Highlight.js upgrade until they enter the eager tail.
    var markdownDefersCodeHighlightUpgrade: Bool {
        get { self[MarkdownDefersCodeHighlightUpgradeKey.self] }
        set { self[MarkdownDefersCodeHighlightUpgradeKey.self] = newValue }
    }
}
