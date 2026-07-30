import SwiftUI

/// Shared motion curves for timeline disclosures and other chrome expand/collapse.
///
/// Disclosure panel height must use **fixed-duration** easing — not springs.
/// Springs emit micro overshoot/corrections that re-measure the timeline row
/// every frame and read as jitter against `NSTableView` row geometry.
enum JinMotion {
    /// Wall-clock duration for disclosure height (SwiftUI + table stay matched).
    static let disclosureDuration: TimeInterval = 0.22

    /// Slightly shorter collapse so the panel gets out of the way cleanly.
    static let disclosureCollapseDuration: TimeInterval = 0.18

    /// Expand: easeInOut, fixed duration — interpolates at constant perceptual
    /// speed with no overshoot that would fight the table row height cache.
    static let disclosureExpand: Animation = .easeInOut(duration: disclosureDuration)

    /// Collapse: same family, slightly snappier.
    static let disclosureCollapse: Animation = .easeInOut(duration: disclosureCollapseDuration)

    /// Default when direction is unknown.
    static let disclosure: Animation = disclosureExpand

    /// Chevron may stay a short critically-damped spring — it does not affect
    /// row height, so it cannot jitter the table.
    static let disclosureIndicator: Animation = .spring(response: 0.20, dampingFraction: 1.0)

    /// Hover / micro affordances.
    static let hover: Animation = .easeOut(duration: 0.12)

    static func disclosure(expanding: Bool) -> Animation {
        expanding ? disclosureExpand : disclosureCollapse
    }

    static func disclosureDuration(expanding: Bool) -> TimeInterval {
        expanding ? disclosureDuration : disclosureCollapseDuration
    }
}
