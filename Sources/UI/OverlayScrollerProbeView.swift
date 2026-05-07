import AppKit

/// An NSView probe that locates its nearest NSScrollView - either as
/// an ancestor or as a sibling in the view hierarchy - and applies
/// overlay-style scrollers when the app preference is enabled.
///
/// Overlay scrollers fade in when the user scrolls and fade out when idle.
/// This is opt-in via the "Use overlay scrollbars" preference so that
/// users who rely on always-visible scrollbars for accessibility can
/// keep the system default.
final class OverlayScrollerProbeView: NSView {
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
