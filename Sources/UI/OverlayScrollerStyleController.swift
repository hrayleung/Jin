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
