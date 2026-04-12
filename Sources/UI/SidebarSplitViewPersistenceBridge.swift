#if os(macOS)
import AppKit
import SwiftUI

struct SidebarSplitViewPersistenceBridge: NSViewRepresentable {
    let desiredSidebarWidth: CGFloat
    let isSidebarVisible: Bool
    let onSidebarWidthChange: (Double) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onSidebarWidthChange = onSidebarWidthChange
        view.update(
            desiredSidebarWidth: desiredSidebarWidth,
            isSidebarVisible: isSidebarVisible
        )
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onSidebarWidthChange = onSidebarWidthChange
        nsView.update(
            desiredSidebarWidth: desiredSidebarWidth,
            isSidebarVisible: isSidebarVisible
        )
    }

    final class ProbeView: NSView {
        var onSidebarWidthChange: ((Double) -> Void)?

        private weak var observedSplitView: NSSplitView?
        private var resizeObserver: NSObjectProtocol?
        private var desiredSidebarWidth = SidebarWidthPersistence.defaultWidth
        private var isSidebarVisible = true
        private var lastAppliedSidebarWidth: CGFloat?
        private var pendingRestore = true

        deinit {
            stopObservingSplitView()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshAttachment()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            refreshAttachment()
        }

        override func layout() {
            super.layout()
            refreshAttachment()
            applyDesiredSidebarWidthIfNeeded()
        }

        func update(desiredSidebarWidth: CGFloat, isSidebarVisible: Bool) {
            self.desiredSidebarWidth = SidebarWidthPersistence.clamped(desiredSidebarWidth)
            let becameVisible = !self.isSidebarVisible && isSidebarVisible
            self.isSidebarVisible = isSidebarVisible
            if becameVisible {
                pendingRestore = true
            }
            refreshAttachment()
            applyDesiredSidebarWidthIfNeeded(force: becameVisible)
        }

        private func refreshAttachment() {
            guard let splitView = findEnclosingSplitView() else { return }
            guard observedSplitView !== splitView else { return }

            stopObservingSplitView()
            observedSplitView = splitView
            pendingRestore = true
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self] _ in
                self?.persistCurrentSidebarWidthIfNeeded()
            }

            DispatchQueue.main.async { [weak self] in
                self?.applyDesiredSidebarWidthIfNeeded(force: true)
                self?.persistCurrentSidebarWidthIfNeeded()
            }
        }

        private func stopObservingSplitView() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            observedSplitView = nil
        }

        private func findEnclosingSplitView() -> NSSplitView? {
            var currentView: NSView? = self
            while let view = currentView {
                if let splitView = view as? NSSplitView {
                    return splitView
                }
                currentView = view.superview
            }
            return nil
        }

        private func applyDesiredSidebarWidthIfNeeded(force: Bool = false) {
            guard isSidebarVisible else { return }
            guard let splitView = observedSplitView else { return }
            guard splitView.subviews.count > 1, splitView.bounds.width > 0 else { return }
            guard let currentWidth = currentSidebarWidth(in: splitView) else { return }

            let shouldApplyStoredWidth =
                force
                || pendingRestore
                || lastAppliedSidebarWidth == nil
                || abs((lastAppliedSidebarWidth ?? currentWidth) - desiredSidebarWidth) > 0.5

            guard shouldApplyStoredWidth else { return }

            if abs(currentWidth - desiredSidebarWidth) <= 0.5 {
                lastAppliedSidebarWidth = desiredSidebarWidth
                pendingRestore = false
                return
            }

            splitView.setPosition(desiredSidebarWidth, ofDividerAt: 0)
            splitView.adjustSubviews()

            lastAppliedSidebarWidth = desiredSidebarWidth
            pendingRestore = false

            DispatchQueue.main.async { [weak self] in
                self?.persistCurrentSidebarWidthIfNeeded()
            }
        }

        private func persistCurrentSidebarWidthIfNeeded() {
            guard isSidebarVisible else { return }
            guard let splitView = observedSplitView else { return }
            guard let currentWidth = currentSidebarWidth(in: splitView) else { return }
            guard let widthToPersist = SidebarWidthPersistence.persistedWidth(from: currentWidth) else { return }

            lastAppliedSidebarWidth = CGFloat(widthToPersist)
            onSidebarWidthChange?(widthToPersist)
        }

        private func currentSidebarWidth(in splitView: NSSplitView) -> CGFloat? {
            guard let sidebarView = splitView.subviews.first else { return nil }
            let width = sidebarView.frame.width
            guard width.isFinite else { return nil }
            return width
        }
    }
}
#endif
