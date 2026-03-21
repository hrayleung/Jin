import SwiftUI
import AppKit

struct ScrollViewPinObserver: NSViewRepresentable {
    @Binding var isPinnedToBottom: Bool
    let bottomTolerance: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPinnedToBottom: $isPinnedToBottom,
            bottomTolerance: bottomTolerance
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = PinObserverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bottomTolerance = bottomTolerance
        guard let view = nsView as? PinObserverNSView else { return }
        view.coordinator = context.coordinator
        context.coordinator.attachIfNeeded(to: view)
    }

    final class Coordinator: NSObject {
        private let isPinnedToBottom: Binding<Bool>
        var bottomTolerance: CGFloat

        private weak var observedScrollView: NSScrollView?
        private var clipViewObserver: NSObjectProtocol?
        private var documentFrameObserver: NSObjectProtocol?
        private var attachAttemptCount = 0
        private var hasLoggedMissingScrollView = false
        private var lastReportedPinned: Bool?

        init(isPinnedToBottom: Binding<Bool>, bottomTolerance: CGFloat) {
            self.isPinnedToBottom = isPinnedToBottom
            self.bottomTolerance = bottomTolerance
        }

        deinit {
            detach()
        }

        func attachIfNeeded(to view: NSView) {
            if let scrollView = locateScrollView(from: view) {
                attach(to: scrollView)
                return
            }

            guard view.window != nil,
                  view.superview != nil,
                  attachAttemptCount < 8 else { return }

            attachAttemptCount += 1
            if !hasLoggedMissingScrollView && attachAttemptCount >= 3 {
                hasLoggedMissingScrollView = true
                ChatScrollDebug.log("pin observer could not find NSScrollView yet")
            }

            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.attachIfNeeded(to: view)
            }
        }

        private func attach(to scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else {
                updatePinnedState(for: scrollView)
                return
            }

            detach()
            observedScrollView = scrollView
            attachAttemptCount = 0
            lastReportedPinned = nil
            hasLoggedMissingScrollView = false
            ChatScrollDebug.log("pin observer attached")

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipViewObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.updatePinnedState(for: scrollView)
            }

            if let documentView = scrollView.documentView {
                documentView.postsFrameChangedNotifications = true
                documentFrameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView else { return }
                    self.updatePinnedState(for: scrollView)
                }
            }

            updatePinnedState(for: scrollView)
        }

        private func locateScrollView(from view: NSView) -> NSScrollView? {
            if let scrollView = view.enclosingScrollView {
                return scrollView
            }

            var current: NSView? = view.superview
            while let candidate = current {
                if let scrollView = candidate as? NSScrollView {
                    return scrollView
                }
                if let scrollView = candidate.enclosingScrollView {
                    return scrollView
                }
                current = candidate.superview
            }

            return nil
        }

        private func detach() {
            if let clipViewObserver {
                NotificationCenter.default.removeObserver(clipViewObserver)
                self.clipViewObserver = nil
            }
            if let documentFrameObserver {
                NotificationCenter.default.removeObserver(documentFrameObserver)
                self.documentFrameObserver = nil
            }
            observedScrollView = nil
        }

        private func updatePinnedState(for scrollView: NSScrollView) {
            guard scrollView.window != nil,
                  let documentView = scrollView.documentView else { return }

            let visibleRect = scrollView.contentView.documentVisibleRect
            let documentRect = documentView.bounds
            let distanceFromBottom: CGFloat

            if documentView.isFlipped {
                distanceFromBottom = max(0, documentRect.maxY - visibleRect.maxY)
            } else {
                distanceFromBottom = max(0, visibleRect.minY - documentRect.minY)
            }

            let isPinned = distanceFromBottom <= max(80, bottomTolerance)
            guard lastReportedPinned != isPinned else { return }
            lastReportedPinned = isPinned
            ChatScrollDebug.log(
                "pin observer update distance=\(String(format: "%.1f", distanceFromBottom)) " +
                "tolerance=\(String(format: "%.1f", max(80, bottomTolerance))) " +
                "isPinned=\(isPinned)"
            )
            isPinnedToBottom.wrappedValue = isPinned
        }
    }
}

private final class PinObserverNSView: NSView {
    weak var coordinator: ScrollViewPinObserver.Coordinator?

    override var isOpaque: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        coordinator?.attachIfNeeded(to: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.attachIfNeeded(to: self)
    }
}
