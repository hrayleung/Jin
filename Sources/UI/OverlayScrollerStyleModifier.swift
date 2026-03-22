import SwiftUI
import AppKit
import ObjectiveC.runtime

private var overlayOriginalAutohidesAssociationKey: UInt8 = 0

@MainActor
final class OverlayScrollerStyleController {
    static let shared = OverlayScrollerStyleController()

    private var installed = false
    private var defaultsObserver: NSObjectProtocol?
    private var lastKnownPreference = overlayScrollbarsEnabled

    static var overlayScrollbarsEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKeys.useOverlayScrollbars) as? Bool ?? true
    }

    func installIfNeeded() {
        guard !installed else { return }
        installed = true

        swizzlePreferredScrollerStyleIfNeeded()
        swizzleScrollViewScrollerStyleSetterIfNeeded()
        observePreferenceChanges()
    }

    func configure(_ scrollView: NSScrollView) {
        storeOriginalAutohidesIfNeeded(for: scrollView)

        if Self.overlayScrollbarsEnabled {
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
        } else {
            restoreOriginalAutohidesIfNeeded(for: scrollView)
            scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
        }
    }

    func refreshAllScrollViews() {
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            refreshScrollViews(in: contentView)
        }
    }

    private func refreshScrollViews(in rootView: NSView) {
        var queue = [rootView]

        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? NSScrollView {
                configure(scrollView)
            }
            queue.append(contentsOf: view.subviews)
        }
    }

    private func storeOriginalAutohidesIfNeeded(for scrollView: NSScrollView) {
        guard objc_getAssociatedObject(scrollView, &overlayOriginalAutohidesAssociationKey) == nil else { return }
        objc_setAssociatedObject(
            scrollView,
            &overlayOriginalAutohidesAssociationKey,
            NSNumber(value: scrollView.autohidesScrollers),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func restoreOriginalAutohidesIfNeeded(for scrollView: NSScrollView) {
        guard let original = objc_getAssociatedObject(
            scrollView,
            &overlayOriginalAutohidesAssociationKey
        ) as? NSNumber else {
            return
        }
        scrollView.autohidesScrollers = original.boolValue
    }

    private func observePreferenceChanges() {
        guard defaultsObserver == nil else { return }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentPreference = Self.overlayScrollbarsEnabled
                guard currentPreference != self.lastKnownPreference else { return }
                self.lastKnownPreference = currentPreference
                self.refreshAllScrollViews()
            }
        }
    }
}

private extension OverlayScrollerStyleController {
    func swizzlePreferredScrollerStyleIfNeeded() {
        guard
            let originalMethod = class_getClassMethod(NSScroller.self, #selector(getter: NSScroller.preferredScrollerStyle)),
            let swizzledMethod = class_getClassMethod(NSScroller.self, #selector(NSScroller.jin_preferredScrollerStyle))
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    func swizzleScrollViewScrollerStyleSetterIfNeeded() {
        guard
            let originalMethod = class_getInstanceMethod(NSScrollView.self, #selector(setter: NSScrollView.scrollerStyle)),
            let swizzledMethod = class_getInstanceMethod(NSScrollView.self, #selector(NSScrollView.jin_setScrollerStyle(_:)))
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

private extension NSScroller {
    @objc class func jin_preferredScrollerStyle() -> NSScroller.Style {
        if OverlayScrollerStyleController.overlayScrollbarsEnabled {
            return .overlay
        }
        return jin_preferredScrollerStyle()
    }
}

private extension NSScrollView {
    @objc func jin_setScrollerStyle(_ style: NSScroller.Style) {
        let resolvedStyle: NSScroller.Style
        if OverlayScrollerStyleController.overlayScrollbarsEnabled {
            resolvedStyle = .overlay
        } else {
            resolvedStyle = style
        }

        jin_setScrollerStyle(resolvedStyle)
    }
}

@MainActor
struct OverlayScrollViewCandidateResolver {
    private let maxAncestorDepth = 12

    func resolveBestCandidate(for probeView: NSView) -> NSScrollView? {
        if let enclosingScrollView = probeView.enclosingScrollView {
            return enclosingScrollView
        }

        let coordinateSpaceRoot = rootView(for: probeView)
        let candidates = collectCandidates(around: probeView)
        guard !candidates.isEmpty else { return nil }

        let probeRect = probeView.convert(probeView.bounds, to: coordinateSpaceRoot)

        return candidates.max { lhs, rhs in
            compare(lhs, rhs, probeRect: probeRect, coordinateSpaceRoot: coordinateSpaceRoot) == .orderedAscending
        }?.scrollView
    }

    private func collectCandidates(around probeView: NSView) -> [OverlayScrollViewCandidate] {
        var candidates: [OverlayScrollViewCandidate] = []
        var seen = Set<ObjectIdentifier>()
        var current: NSView = probeView
        var ancestorDepth = 0

        while ancestorDepth <= maxAncestorDepth, let parent = current.superview {
            if let scrollView = parent as? NSScrollView {
                appendCandidate(
                    scrollView,
                    ancestorDepth: ancestorDepth,
                    to: &candidates,
                    seen: &seen,
                    relativeTo: probeView
                )
            }

            for sibling in parent.subviews where sibling !== current {
                appendDescendantCandidates(
                    in: sibling,
                    ancestorDepth: ancestorDepth,
                    to: &candidates,
                    seen: &seen,
                    relativeTo: probeView
                )
            }

            current = parent
            ancestorDepth += 1
        }

        return candidates
    }

    private func appendDescendantCandidates(
        in rootView: NSView,
        ancestorDepth: Int,
        to candidates: inout [OverlayScrollViewCandidate],
        seen: inout Set<ObjectIdentifier>,
        relativeTo probeView: NSView
    ) {
        var queue = [rootView]

        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? NSScrollView {
                appendCandidate(
                    scrollView,
                    ancestorDepth: ancestorDepth,
                    to: &candidates,
                    seen: &seen,
                    relativeTo: probeView
                )
                continue
            }

            queue.append(contentsOf: view.subviews)
        }
    }

    private func appendCandidate(
        _ scrollView: NSScrollView,
        ancestorDepth: Int,
        to candidates: inout [OverlayScrollViewCandidate],
        seen: inout Set<ObjectIdentifier>,
        relativeTo probeView: NSView
    ) {
        let identifier = ObjectIdentifier(scrollView)
        guard seen.insert(identifier).inserted else { return }
        candidates.append(
            OverlayScrollViewCandidate(
                scrollView: scrollView,
                ancestorDepth: ancestorDepth
            )
        )
    }

    private func rootView(for probeView: NSView) -> NSView {
        var current = probeView
        while let parent = current.superview {
            current = parent
        }
        return current
    }

    private func compare(
        _ lhs: OverlayScrollViewCandidate,
        _ rhs: OverlayScrollViewCandidate,
        probeRect: NSRect,
        coordinateSpaceRoot: NSView
    ) -> ComparisonResult {
        let lhsIntersection = lhs.intersectionArea(with: probeRect, in: coordinateSpaceRoot)
        let rhsIntersection = rhs.intersectionArea(with: probeRect, in: coordinateSpaceRoot)
        if lhsIntersection != rhsIntersection {
            return lhsIntersection < rhsIntersection ? .orderedAscending : .orderedDescending
        }

        let lhsDistance = lhs.distanceSquared(to: probeRect, in: coordinateSpaceRoot)
        let rhsDistance = rhs.distanceSquared(to: probeRect, in: coordinateSpaceRoot)
        if lhsDistance != rhsDistance {
            return lhsDistance > rhsDistance ? .orderedAscending : .orderedDescending
        }

        if lhs.ancestorDepth != rhs.ancestorDepth {
            return lhs.ancestorDepth > rhs.ancestorDepth ? .orderedAscending : .orderedDescending
        }

        return .orderedSame
    }
}

@MainActor
private struct OverlayScrollViewCandidate {
    let scrollView: NSScrollView
    let ancestorDepth: Int

    func intersectionArea(with otherRect: NSRect, in coordinateSpaceRoot: NSView) -> CGFloat {
        let candidateRect = rect(in: coordinateSpaceRoot)
        return candidateRect.intersection(otherRect).area
    }

    func distanceSquared(to otherRect: NSRect, in coordinateSpaceRoot: NSView) -> CGFloat {
        let candidateRect = rect(in: coordinateSpaceRoot)
        let dx = candidateRect.midX - otherRect.midX
        let dy = candidateRect.midY - otherRect.midY
        return (dx * dx) + (dy * dy)
    }

    private func rect(in coordinateSpaceRoot: NSView) -> NSRect {
        scrollView.convert(scrollView.bounds, to: coordinateSpaceRoot)
    }
}

private extension NSRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

/// An NSView probe that locates its nearest NSScrollView — either as
/// an ancestor or as a sibling in the view hierarchy — and applies
/// overlay-style scrollers when the app preference is enabled.
///
/// Overlay scrollers fade in when the user scrolls and fade out when idle.
/// This is opt-in via the "Use overlay scrollbars" preference so that
/// users who rely on always-visible scrollbars for accessibility can
/// keep the system default.
private final class OverlayScrollerProbeView: NSView {
    private let candidateResolver = OverlayScrollViewCandidateResolver()
    private var remainingAttachAttempts = 0
    private var pendingAttachWorkItem: DispatchWorkItem?
    private var scrollerStyleObserver: NSObjectProtocol?
    private weak var targetScrollView: NSScrollView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleAttach(resetAttempts: true)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleAttach(resetAttempts: true)
    }

    override func removeFromSuperview() {
        cancelPendingAttach()
        stopObserving()
        super.removeFromSuperview()
    }

    deinit {
        cancelPendingAttach()
        stopObserving()
    }

    func refreshAttachment() {
        scheduleAttach(resetAttempts: targetScrollView == nil)
    }

    private func scheduleAttach(resetAttempts: Bool) {
        cancelPendingAttach()
        if resetAttempts {
            remainingAttachAttempts = 8
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptAttach()
        }
        pendingAttachWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func attemptAttach() {
        pendingAttachWorkItem = nil

        if let scrollView = candidateResolver.resolveBestCandidate(for: self) {
            targetScrollView = scrollView
            applyOverlayStyle(to: scrollView)
            startObservingStyleChanges()
            remainingAttachAttempts = 0
            return
        }

        if let targetScrollView {
            applyOverlayStyle(to: targetScrollView)
            return
        }

        guard remainingAttachAttempts > 0 else { return }
        remainingAttachAttempts -= 1
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptAttach()
        }
        pendingAttachWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func applyOverlayStyle(to scrollView: NSScrollView) {
        OverlayScrollerStyleController.shared.configure(scrollView)
    }

    private func startObservingStyleChanges() {
        guard scrollerStyleObserver == nil else { return }
        scrollerStyleObserver = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let scrollView = self.targetScrollView else { return }
            self.applyOverlayStyle(to: scrollView)
        }
    }

    private func stopObserving() {
        if let observer = scrollerStyleObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollerStyleObserver = nil
        }
        targetScrollView = nil
    }

    private func cancelPendingAttach() {
        pendingAttachWorkItem?.cancel()
        pendingAttachWorkItem = nil
    }
}

private struct OverlayScrollerStyleViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollerProbeView {
        OverlayScrollerProbeView()
    }

    func updateNSView(_ nsView: OverlayScrollerProbeView, context: Context) {
        nsView.refreshAttachment()
    }
}

extension View {
    /// Conditionally applies overlay-style scrollers to the nearest
    /// NSScrollView, gated by the ``AppPreferenceKeys/useOverlayScrollbars``
    /// preference. When disabled, the system-wide scroller style is respected.
    func overlayScrollerStyle() -> some View {
        modifier(OverlayScrollerStyleModifier())
    }
}

private struct OverlayScrollerStyleModifier: ViewModifier {
    @AppStorage(AppPreferenceKeys.useOverlayScrollbars) private var useOverlayScrollbars = true

    func body(content: Content) -> some View {
        if useOverlayScrollbars {
            content.background(OverlayScrollerStyleViewRepresentable())
        } else {
            content
        }
    }
}
