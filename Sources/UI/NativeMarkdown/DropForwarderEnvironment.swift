import AppKit
import SwiftUI

/// Per-window drop forwarding reference. Each `ChatView` creates one and
/// injects it into the environment so dropped files reach the chat
/// composer's attachment pipeline. The native markdown renderer's
/// `NSTextView`s don't accept drops by default, so this currently routes
/// nothing — but the env value is kept for any future blocks that might
/// need to intercept drops, and for parity with the previous WKWebView-era
/// installation hook in `ChatView+Lifecycle`.
final class DropForwarderRef {
    var onDragTargetChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?
}

private struct DropForwarderRefKey: EnvironmentKey {
    static let defaultValue: DropForwarderRef? = nil
}

extension EnvironmentValues {
    var dropForwarderRef: DropForwarderRef? {
        get { self[DropForwarderRefKey.self] }
        set { self[DropForwarderRefKey.self] = newValue }
    }
}
