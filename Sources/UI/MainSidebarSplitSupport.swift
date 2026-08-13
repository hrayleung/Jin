import SwiftUI

/// Column-width and animation policy for the main `NavigationSplitView`.
///
/// SwiftUI on macOS animates sidebar visibility by interpolating the split
/// column. A `minWidth` on the split view — or a high `navigationSplitViewColumnWidth(min:)`
/// — fights the collapse-to-zero animation and hitches even with empty
/// children (Hacking with Swift forums, Mar 2025). Keep the column's layout
/// minimum tiny so AppKit can slide, and isolate descendants so they do not
/// inherit that transaction.
enum MainSidebarSplitSupport {
    /// Floor for `navigationSplitViewColumnWidth(min:)`. Must stay well below
    /// `SidebarWidthPersistence.minimumWidth` so hide/show can animate to 0.
    static let animatableColumnMinimumWidth: CGFloat = 1

    static func isVisible(_ visibility: NavigationSplitViewVisibility) -> Bool {
        visibility != .detailOnly
    }

    static func nextVisibility(
        _ visibility: NavigationSplitViewVisibility
    ) -> NavigationSplitViewVisibility {
        isVisible(visibility) ? .detailOnly : .all
    }

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
