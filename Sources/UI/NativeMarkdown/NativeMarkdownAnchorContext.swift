import SwiftUI

/// Environment value carrying the per-anchor selection coordinator and the
/// pre-walked layout used to look up per-block offsets.
struct NativeMarkdownAnchorContext {
    let aggregator: SelectionAggregator
    let layout: NativeAnchorLayout
}

private struct NativeMarkdownAnchorContextKey: EnvironmentKey {
    static let defaultValue: NativeMarkdownAnchorContext? = nil
}

extension EnvironmentValues {
    var nativeMarkdownAnchor: NativeMarkdownAnchorContext? {
        get { self[NativeMarkdownAnchorContextKey.self] }
        set { self[NativeMarkdownAnchorContextKey.self] = newValue }
    }
}
