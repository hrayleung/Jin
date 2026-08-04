import SwiftUI

/// Shared motion curves for timeline disclosures, message appearance, and chrome.
///
/// ## Rules of the road
///
/// 1. **Row-height-driving motion** (disclosure panels) must use **fixed-duration**
///    easing — not springs. Springs emit micro overshoot/corrections that
///    re-measure the timeline row every frame and read as jitter against
///    `NSTableView` row geometry.
/// 2. **Continuous chrome** (wave dots, pulses) must be **time-based** via
///    `TimelineView` (`JinContinuousMotion`) — never `@State + repeatForever`,
///    which freezes mid-pose when an `NSHostingView` reconfigures.
/// 3. **Message appearance** uses opacity/offset only so measured height stays
///    stable for the whole entrance.
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

    /// Chevron rotation — fixed-duration ease matching the panel family so a
    /// killed transaction never leaves a spring mid-angle. Springs used to
    /// look slightly softer but stuck at half-rotation after cell reconfigure.
    static let disclosureIndicator: Animation = .easeInOut(duration: 0.18)

    /// Newly inserted timeline row (opacity + y-offset only).
    static let messageAppearDuration: TimeInterval = 0.22
    static let messageAppear: Animation = .easeOut(duration: messageAppearDuration)

    /// Composer send ↔ stop glyph swap.
    static let sendGlyph: Animation = .easeInOut(duration: 0.16)

    /// Hover / micro affordances.
    static let hover: Animation = .easeOut(duration: 0.12)

    static func disclosure(expanding: Bool) -> Animation {
        expanding ? disclosureExpand : disclosureCollapse
    }

    static func disclosureDuration(expanding: Bool) -> TimeInterval {
        expanding ? disclosureDuration : disclosureCollapseDuration
    }
}
