#if os(macOS)
import AppKit
import QuartzCore
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
        private var lastAppliedSidebarVisibility = true
        private var sidebarVisibilityAnimationGeneration = 0
        private var activeSidebarVisibilityAnimationGeneration: Int?
        private var pendingRestore = true
        private lazy var sidebarWidthPersistor = SidebarWidthPersistence.DebouncedPersistor(
            delay: 0.15,
            schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
            },
            persist: { [weak self] width in
                self?.onSidebarWidthChange?(width)
            }
        )

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
            syncCurrentSidebarStateIfNeeded(animated: false)
        }

        func update(desiredSidebarWidth: CGFloat, isSidebarVisible: Bool) {
            self.desiredSidebarWidth = SidebarWidthPersistence.clamped(desiredSidebarWidth)
            let visibilityChanged = lastAppliedSidebarVisibility != isSidebarVisible
            self.isSidebarVisible = isSidebarVisible
            if visibilityChanged && isSidebarVisible {
                pendingRestore = true
            }
            refreshAttachment()
            syncCurrentSidebarStateIfNeeded(animated: visibilityChanged)
        }

        private func refreshAttachment() {
            guard let splitView = findEnclosingSplitView() else {
                stopObservingSplitView()
                return
            }
            guard observedSplitView !== splitView else { return }

            stopObservingSplitView()
            observedSplitView = splitView
            pendingRestore = true
            activeSidebarVisibilityAnimationGeneration = nil
            lastAppliedSidebarVisibility = !isSidebarVisible
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleCurrentSidebarWidthPersistenceIfNeeded()
            }

            DispatchQueue.main.async { [weak self] in
                self?.syncCurrentSidebarStateIfNeeded(animated: false, forceWidthRestore: true)
                self?.persistCurrentSidebarWidthIfNeeded()
            }
        }

        private func stopObservingSplitView() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            sidebarWidthPersistor.flush()
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

        private func syncCurrentSidebarStateIfNeeded(animated: Bool, forceWidthRestore: Bool = false) {
            if lastAppliedSidebarVisibility != isSidebarVisible {
                setSidebarVisibility(isSidebarVisible, animated: animated)
            } else {
                applyDesiredSidebarWidthIfNeeded(force: forceWidthRestore)
            }
        }

        private func applyDesiredSidebarWidthIfNeeded(force: Bool = false) {
            guard activeSidebarVisibilityAnimationGeneration == nil else { return }
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
                self?.scheduleCurrentSidebarWidthPersistenceIfNeeded()
            }
        }

        private func setSidebarVisibility(_ isVisible: Bool, animated: Bool) {
            guard let splitView = observedSplitView else { return }
            guard splitView.subviews.count > 1, splitView.bounds.width > 0 else { return }

            let targetWidth = isVisible ? desiredSidebarWidth : 0
            guard let currentWidth = currentSidebarWidth(in: splitView) else { return }

            lastAppliedSidebarVisibility = isVisible
            sidebarVisibilityAnimationGeneration += 1
            let animationGeneration = sidebarVisibilityAnimationGeneration
            activeSidebarVisibilityAnimationGeneration = animationGeneration

            if abs(currentWidth - targetWidth) <= 0.5 {
                finishSidebarVisibilityChange(
                    isVisible: isVisible,
                    targetWidth: targetWidth,
                    animationGeneration: animationGeneration
                )
                return
            }

            let applyTargetWidth = {
                splitView.setPosition(targetWidth, ofDividerAt: 0)
                splitView.adjustSubviews()
            }

            guard animated, splitView.window != nil else {
                applyTargetWidth()
                finishSidebarVisibilityChange(
                    isVisible: isVisible,
                    targetWidth: targetWidth,
                    animationGeneration: animationGeneration
                )
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                splitView.animator().setPosition(targetWidth, ofDividerAt: 0)
            } completionHandler: { [weak self] in
                self?.finishSidebarVisibilityChange(
                    isVisible: isVisible,
                    targetWidth: targetWidth,
                    animationGeneration: animationGeneration
                )
            }
        }

        private func finishSidebarVisibilityChange(
            isVisible: Bool,
            targetWidth: CGFloat,
            animationGeneration: Int
        ) {
            guard sidebarVisibilityAnimationGeneration == animationGeneration else { return }
            defer {
                if activeSidebarVisibilityAnimationGeneration == animationGeneration {
                    activeSidebarVisibilityAnimationGeneration = nil
                }
            }
            guard let splitView = observedSplitView else { return }

            splitView.setPosition(targetWidth, ofDividerAt: 0)
            splitView.adjustSubviews()

            if isVisible {
                lastAppliedSidebarWidth = targetWidth
                pendingRestore = false
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleCurrentSidebarWidthPersistenceIfNeeded()
                }
            } else {
                lastAppliedSidebarWidth = nil
            }
        }

        private func scheduleCurrentSidebarWidthPersistenceIfNeeded() {
            guard activeSidebarVisibilityAnimationGeneration == nil else { return }
            guard isSidebarVisible else { return }
            guard let splitView = observedSplitView else { return }
            guard let currentWidth = currentSidebarWidth(in: splitView) else { return }
            guard let widthToPersist = SidebarWidthPersistence.persistedWidth(from: currentWidth) else { return }

            sidebarWidthPersistor.schedule(width: widthToPersist)
        }

        private func persistCurrentSidebarWidthIfNeeded() {
            guard activeSidebarVisibilityAnimationGeneration == nil else { return }
            guard isSidebarVisible else { return }
            guard let splitView = observedSplitView else { return }
            guard let currentWidth = currentSidebarWidth(in: splitView) else { return }
            guard let widthToPersist = SidebarWidthPersistence.persistedWidth(from: currentWidth) else { return }

            lastAppliedSidebarWidth = CGFloat(widthToPersist)
            sidebarWidthPersistor.flush()
            onSidebarWidthChange?(widthToPersist)
        }

        private func currentSidebarWidth(in splitView: NSSplitView) -> CGFloat? {
            guard let sidebarView = sidebarContainerView(in: splitView) else { return nil }
            let width = sidebarView.frame.width
            guard width.isFinite else { return nil }
            return width
        }

        private func sidebarContainerView(in splitView: NSSplitView) -> NSView? {
            var currentView: NSView? = self
            var candidate: NSView?
            while let view = currentView {
                if view === splitView {
                    return candidate
                }
                candidate = view
                currentView = view.superview
            }

            return splitView.subviews.first
        }
    }
}
#endif
