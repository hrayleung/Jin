import SwiftUI

/// Animation policy for the main `NavigationSplitView`.
///
/// Visibility mapping and column-width bounds live in `MainSidebarVisibility`.
/// This type only decides whether a visibility change may interpolate.
enum MainSidebarSplitSupport {
    static var suppressedAnimationTransaction: Transaction {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        return transaction
    }

    /// An open conversation is an `NSTableView` of hosted markdown cells.
    /// Interpolating the split column remasures every visible row (hitch).
    /// Pinning or rasterizing that table made the content fly. Snap instead:
    /// one layout at the final size. Empty detail stays animated.
    static func shouldSnapColumnChange(
        reduceMotion: Bool,
        hasOpenConversation: Bool
    ) -> Bool {
        reduceMotion || hasOpenConversation
    }
}

extension View {
    /// Stops this subtree from interpolating when `columnVisibility` flips.
    /// The split view itself still animates in AppKit; descendants must not
    /// join that transaction or markdown / List / TextField reflow every tick.
    func isolatedFromSidebarColumnAnimation(
        _ visibility: NavigationSplitViewVisibility
    ) -> some View {
        animation(nil, value: visibility)
    }
}
