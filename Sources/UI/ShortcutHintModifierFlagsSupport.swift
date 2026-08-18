import AppKit

enum ShortcutHintModifierFlagsSupport {
    /// Live modifier state of the whole login session, after OS remapping.
    ///
    /// Not `NSEvent.modifierFlags`: that class property only mirrors the
    /// app's own event stream. Measured on-device, it lags the event being
    /// delivered (a ⌘ press sampled through it read "none", the release read
    /// "⌘ still down"), and it stays stale forever when the release happens
    /// while the app is in the background (⌘-Tab away). The window-server
    /// session state has neither failure mode, so polling it can never get
    /// stuck on a missed or misordered key transition.
    static func currentLogicalModifiers() -> AppShortcutModifiers {
        AppShortcutModifiers(cgFlags: CGEventSource.flagsState(.combinedSessionState))
    }

    static func modifier(forKeyCode keyCode: UInt16) -> AppShortcutModifiers? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        default: return nil
        }
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        modifier(forKeyCode: keyCode) != nil
            || keyCode == 57 // Caps Lock
            || keyCode == 63 // Fn / Globe
    }

    /// Resolves who owns the keyboard.
    ///
    /// Returns `.unknown` rather than "no" whenever the answer cannot be
    /// established — the badge treats that as "show", because the alternative
    /// is a silent app-wide blackout that looks exactly like the feature being
    /// broken. Only a sheet narrows the hints to a single window.
    static func focus(
        hostWindows: [NSWindow],
        isAppActive: Bool,
        keyWindow: NSWindow?,
        mainWindow: NSWindow?,
        lastKeyWindow: NSWindow?
    ) -> ShortcutHintFocus {
        guard isAppActive else { return .foreign }
        guard !hostWindows.isEmpty else { return .unknown }

        if let keyWindow, belongsToHostHierarchy(keyWindow, hostWindows: hostWindows) {
            return focus(ofHostWindow: keyWindow)
        }

        // Either ⌘ temporarily cleared `keyWindow`, or the keyboard sits in a
        // window of ours that hosts no badges — Settings, a Sparkle prompt,
        // an alert, a toast. Measured on-device, such a window held key for
        // 30+ seconds and blacked out every badge in the app. The app is
        // still frontmost either way, so resolve against the most recent
        // host window instead of going dark.
        if let window = activeWindow(
            hostWindows: hostWindows,
            isAppActive: isAppActive,
            keyWindow: nil,
            mainWindow: mainWindow,
            lastKeyWindow: lastKeyWindow
        ) {
            return focus(ofHostWindow: window)
        }
        return .unknown
    }

    private static func focus(ofHostWindow window: NSWindow) -> ShortcutHintFocus {
        window.sheetParent == nil ? .host : .sheet(ObjectIdentifier(window))
    }

    static func isHostActive(
        hostWindows: [NSWindow],
        isAppActive: Bool,
        keyWindow: NSWindow?,
        mainWindow: NSWindow?
    ) -> Bool {
        activeWindow(
            hostWindows: hostWindows,
            isAppActive: isAppActive,
            keyWindow: keyWindow,
            mainWindow: mainWindow,
            lastKeyWindow: nil
        ) != nil
    }

    static func activeWindow(
        hostWindows: [NSWindow],
        isAppActive: Bool,
        keyWindow: NSWindow?,
        mainWindow: NSWindow?,
        lastKeyWindow: NSWindow?
    ) -> NSWindow? {
        guard isAppActive, !hostWindows.isEmpty else { return nil }

        if let keyWindow {
            return belongsToHostHierarchy(keyWindow, hostWindows: hostWindows)
                ? keyWindow
                : nil
        }

        if let lastKeyWindow,
           lastKeyWindow.isVisible,
           belongsToHostHierarchy(lastKeyWindow, hostWindows: hostWindows) {
            return lastKeyWindow
        }

        if let mainWindow,
           belongsToHostHierarchy(mainWindow, hostWindows: hostWindows) {
            return mainWindow
        }
        return nil
    }

    /// Sheets and child windows count as their host: a badge inside a sheet
    /// must keep working, while badges on the window behind it must not.
    static func belongsToHostHierarchy(
        _ window: NSWindow,
        hostWindows: [NSWindow]
    ) -> Bool {
        var candidate: NSWindow? = window
        var visited: Set<ObjectIdentifier> = []

        while let current = candidate {
            let identifier = ObjectIdentifier(current)
            guard visited.insert(identifier).inserted else { return false }
            if hostWindows.contains(where: { $0 === current }) {
                return true
            }
            candidate = current.sheetParent ?? current.parent
        }
        return false
    }
}
