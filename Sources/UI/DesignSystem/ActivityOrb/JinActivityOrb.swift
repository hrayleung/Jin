import SwiftUI

/// Dotted thought-orb for in-flight chat verbs.
///
/// Animation is owned by compositor-driven AppKit layers. The SwiftUI wrapper
/// is fixed-size, so a table-hosted `NSHostingView` is never invalidated by a
/// frame.
enum JinActivityOrbPose: Equatable, Sendable {
    /// In-flight verb. Clock-driven unless `paused` / reduce-motion.
    case live
    /// Finished thought. `solving` rest — lattice clicked back, not a
    /// frozen live frame and not a face-on ring.
    case settled
}

struct JinActivityOrb: View {
    var kind: JinActivityKind
    var size: JinActivityOrbSize = .inline
    var paused: Bool = false
    var pose: JinActivityOrbPose = .live
    /// When false (default) the orb is decorative; the parent owns the label.
    var announces: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = CGFloat(size.value)
        let settled = pose == .settled
        JinActivityOrbRepresentable(
            kind: kind,
            size: size,
            paused: settled || paused || reduceMotion,
            pose: pose,
            isDark: colorScheme == .dark
        )
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(announces ? Text(kind.accessibilityLabel) : Text(""))
        .accessibilityHidden(!announces)
        .accessibilityAddTraits(announces ? .isImage : [])
    }
}

private struct JinActivityOrbRepresentable: NSViewRepresentable {
    var kind: JinActivityKind
    var size: JinActivityOrbSize
    var paused: Bool
    var pose: JinActivityOrbPose
    var isDark: Bool

    func makeNSView(context: Context) -> JinActivityOrbNSView {
        let view = JinActivityOrbNSView()
        view.apply(kind: kind, size: size, paused: paused, pose: pose, isDark: isDark)
        return view
    }

    func updateNSView(_ nsView: JinActivityOrbNSView, context: Context) {
        nsView.apply(kind: kind, size: size, paused: paused, pose: pose, isDark: isDark)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: JinActivityOrbNSView,
        context: Context
    ) -> CGSize? {
        let side = CGFloat(size.value)
        return CGSize(width: side, height: side)
    }
}
