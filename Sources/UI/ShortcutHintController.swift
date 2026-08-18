import AppKit
import SwiftUI

/// Reveals keyboard-shortcut badges while ⌘ is held.
///
/// The rule that keeps this reliable: **the sampler decides, events only hurry
/// it up.** Every tick re-derives the whole reveal state from live sources
/// (the window-server session modifier state, `NSApp.keyWindow`), so a
/// swallowed `flagsChanged`, a menu-tracking run loop or a stalled main queue
/// can cost at most one tick. Nothing here accumulates a flag that can leave
/// the feature stuck off for the rest of the session — which is exactly how
/// earlier versions failed.
///
/// Two measured failure modes shape the details:
/// - `NSEvent.modifierFlags` lagged the event being delivered (press read
///   "none", release read "⌘ down"), locking every hold out of phase — so
///   event-driven samples use the event's own flags and polls use
///   `CGEventSource.flagsState`, never the class property.
/// - The run-loop timer sat silent for 3+ seconds under main-thread load — so
///   each hold also arms a plain main-queue deadline block, the earliest
///   thing that can possibly run once the thread frees up.
@MainActor
final class ShortcutHintController: ObservableObject {
    static let shared = ShortcutHintController()

    /// Long enough that ⌘C / ⌘N never flash a badge, short enough that a
    /// deliberate "press and look" feels immediate.
    static let holdDelay: TimeInterval = 0.18
    /// Sampling rate while ⌘ is down.
    static let activeSampleInterval: TimeInterval = 1.0 / 30.0
    /// Idle heartbeat. It only has to catch a ⌘ press whose `flagsChanged`
    /// never reached us; the hold delay hides the extra latency.
    static let idleSampleInterval: TimeInterval = 0.2

    @Published private(set) var isRevealed = false
    @Published private(set) var heldModifiers: AppShortcutModifiers = []
    /// Set only while a sheet owns the keyboard, to keep hints off the window
    /// behind it. `nil` — the normal case — means "no restriction".
    @Published private(set) var restrictedWindowID: ObjectIdentifier?

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            ShortcutHintRevealEngine.restartHold(state: &state)
            sample()
        }
    }

    /// Set while the shortcut recorder is capturing keys, so the badges do not
    /// react to the chord being recorded.
    var isCaptureActive = false {
        didSet {
            guard oldValue != isCaptureActive else { return }
            ShortcutHintRevealEngine.restartHold(state: &state)
            sample()
        }
    }

    private var state = ShortcutHintRevealState()
    private var lastFocus: ShortcutHintFocus = .unknown
    private var monitors: [Any] = []
    private var appObservers: [NSObjectProtocol] = []
    private var sampleTimer: Timer?
    private var sampleTimerInterval: TimeInterval?
    private var revealDeadlineGeneration = 0
    private let hostWindows = NSHashTable<NSWindow>.weakObjects()
    private weak var lastEligibleKeyWindow: NSWindow?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: AppPreferenceKeys.showShortcutHints) as? Bool ?? true
        startMonitoringIfNeeded()
    }

    deinit {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sampleTimer?.invalidate()
    }

    /// Called by every window that hosts hint badges. Registration is what
    /// lets the controller tell "our window" from Settings or another app.
    func registerHostWindow(_ window: NSWindow) {
        let isNewWindow = !hostWindows.contains(window)
        hostWindows.add(window)
        if window.isKeyWindow {
            lastEligibleKeyWindow = window
        }
        startMonitoringIfNeeded()

        guard isNewWindow else { return }
        // AppKit delivers this from a view-lifecycle callback that can land
        // inside a SwiftUI update pass, where publishing is undefined
        // behaviour. Hop out of the pass before touching @Published state.
        DispatchQueue.main.async { [weak self] in
            self?.sample()
        }
    }

    func startMonitoringIfNeeded() {
        if monitors.isEmpty {
            // These are hints to sample immediately, nothing more. Command-only
            // presses are easily swallowed by menu-bar key-equivalent tracking,
            // so the sampler — not this monitor — is the source of truth.
            let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                // The event's own flags are the truth for this instant. The
                // live-state query can lag the delivery by one transition,
                // which read "⌘ up" during the press and "⌘ down" during the
                // release — locking every later hold out of phase.
                self?.sample(eventModifiers: AppShortcutModifiers(
                    eventFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                ))
                return event
            }
            let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
                return event
            }
            monitors = [flagsMonitor, keyMonitor].compactMap { $0 }
        }

        if appObservers.isEmpty {
            let center = NotificationCenter.default
            appObservers = [
                center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        // ⌘-Tabbing back in must not count time spent in the
                        // other app as a deliberate hold.
                        self?.restartHoldAndSample()
                    }
                },
                center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.restartHoldAndSample()
                    }
                },
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.sample()
                    }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.sample()
                    }
                }
            ]
        }

        syncTimer()
    }

    private func handleKeyDown(_ event: NSEvent) {
        let eventModifiers = AppShortcutModifiers(
            eventFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        guard !ShortcutHintModifierFlagsSupport.isModifierKeyCode(event.keyCode) else {
            sample(eventModifiers: eventModifiers)
            return
        }

        // Empty-character keyDowns show up during IME composition and menu
        // tracking. Those are not a shortcut and must not cancel the hold.
        guard event.charactersIgnoringModifiers?.isEmpty == false else {
            sample(eventModifiers: eventModifiers)
            return
        }

        ShortcutHintRevealEngine.markChord(
            state: &state,
            eventModifiers: eventModifiers
        )
        // Drop the badges on the same run-loop turn as the keypress, then let
        // the sampler take it from there.
        publishState()
        sample(eventModifiers: eventModifiers)
    }

    private func restartHoldAndSample() {
        ShortcutHintRevealEngine.restartHold(state: &state)
        sample()
    }

    /// `eventModifiers` carries the flags of the event that triggered this
    /// sample; timer- and notification-driven samples pass nothing and read
    /// the live session state instead.
    private func sample(eventModifiers: AppShortcutModifiers? = nil) {
        let input = ShortcutHintRevealInput(
            modifiers: eventModifiers ?? ShortcutHintModifierFlagsSupport.currentLogicalModifiers(),
            focus: resolveFocus(),
            isEnabled: isEnabled,
            isCaptureActive: isCaptureActive,
            timestamp: ProcessInfo.processInfo.systemUptime
        )

        state = ShortcutHintRevealEngine.resolve(
            state: state,
            input: input,
            holdDelay: Self.holdDelay
        )
        publishState()
        syncTimer()
        scheduleRevealDeadline()
    }

    /// Compares against the published values rather than a previous snapshot,
    /// so any path that mutates `state` still ends up on screen.
    private func publishState() {
        guard isRevealed != state.isRevealed
            || heldModifiers != state.heldModifiers
            || restrictedWindowID != state.restrictedWindowID else { return }

        if isRevealed != state.isRevealed { isRevealed = state.isRevealed }
        if heldModifiers != state.heldModifiers { heldModifiers = state.heldModifiers }
        if restrictedWindowID != state.restrictedWindowID { restrictedWindowID = state.restrictedWindowID }
    }

    private func resolveFocus() -> ShortcutHintFocus {
        let windows = hostWindows.allObjects
        let keyWindow = NSApp?.keyWindow
        if let keyWindow,
           ShortcutHintModifierFlagsSupport.belongsToHostHierarchy(keyWindow, hostWindows: windows) {
            lastEligibleKeyWindow = keyWindow
        }

        let focus = ShortcutHintModifierFlagsSupport.focus(
            hostWindows: windows,
            isAppActive: isApplicationActive,
            keyWindow: keyWindow,
            mainWindow: NSApp?.mainWindow,
            lastKeyWindow: lastEligibleKeyWindow
        )
        lastFocus = focus
        return focus
    }

    /// `NSApp` is nil until AppKit finishes bootstrapping, and this controller
    /// is created from `JinApp`'s property initializer.
    private var isApplicationActive: Bool {
        NSApp?.isActive ?? false
    }

    private var desiredSampleInterval: TimeInterval? {
        guard isEnabled, !isCaptureActive, isApplicationActive else { return nil }
        return state.commandDownAt == nil ? Self.idleSampleInterval : Self.activeSampleInterval
    }

    /// A one-shot wake at the exact moment the current hold becomes old
    /// enough to reveal. The run-loop timer was measured sitting silent for
    /// 3+ seconds while the main thread was busy; a plain main-queue block
    /// is the earliest thing that can run once it frees up, so the reveal
    /// never waits on timer scheduling. Superseded (via the generation
    /// counter) by every newer sample, and a no-op if the hold has already
    /// revealed, broken, or ended by the time it fires.
    private func scheduleRevealDeadline() {
        revealDeadlineGeneration += 1
        guard let start = state.commandDownAt,
              !state.isRevealed,
              !state.isChordInProgress,
              isEnabled,
              !isCaptureActive,
              lastFocus.allowsReveal else { return }

        let generation = revealDeadlineGeneration
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let remaining = max(0, Self.holdDelay - elapsed) + 0.02
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealDeadlineGeneration == generation else { return }
                self.sample()
            }
        }
    }

    private func syncTimer() {
        guard let interval = desiredSampleInterval else {
            sampleTimer?.invalidate()
            sampleTimer = nil
            sampleTimerInterval = nil
            return
        }
        if let timer = sampleTimer, timer.isValid, sampleTimerInterval == interval {
            return
        }

        sampleTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Installed on RunLoop.main below. Execute synchronously so
            // menu-tracking mode cannot defer a queued Task.
            MainActor.assumeIsolated {
                self?.sample()
            }
        }
        timer.tolerance = interval / 2
        // `.common` keeps sampling while macOS is in a tracking run-loop mode
        // (menus, scrolling, window drags).
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
        sampleTimerInterval = interval
    }
}
