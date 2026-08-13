import SwiftUI

enum MainSidebarVisibility {
    static let defaultIsVisible = true

    static func toggled(_ isVisible: Bool) -> Bool {
        !isVisible
    }

    /// Sidebar visibility is owned exclusively by NavigationSplitView's
    /// `columnVisibility` binding. Anything other than `.detailOnly` is
    /// treated as visible, including `.automatic`.
    static func isVisible(_ visibility: NavigationSplitViewVisibility) -> Bool {
        visibility != .detailOnly
    }

    static func splitVisibility(isVisible: Bool) -> NavigationSplitViewVisibility {
        isVisible ? .all : .detailOnly
    }

    static func toggled(_ visibility: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility {
        splitVisibility(isVisible: !isVisible(visibility))
    }

    /// Tahoe keeps the sidebar-column toolbar item after collapse by
    /// migrating it into the remaining title bar. macOS 14/15 drop it
    /// with the column, so those releases need a detail-side copy.
    static var sidebarToolbarMigratesWhenCollapsed: Bool {
        if #available(macOS 26, *) {
            true
        } else {
            false
        }
    }

    /// Width constraints applied to the sidebar column. A non-zero `min`
    /// keeps the visible column from collapsing into an unusable sliver;
    /// when the column is hidden the range drops to zero so a stale
    /// `min` cannot pin the split item open.
    static func columnWidth(
        isVisible: Bool,
        persistedWidth: Double
    ) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        guard isVisible else {
            return (0, 0, 0)
        }
        return (
            SidebarWidthPersistence.minimumWidth,
            SidebarWidthPersistence.resolvedWidth(from: persistedWidth),
            SidebarWidthPersistence.maximumWidth
        )
    }
}
