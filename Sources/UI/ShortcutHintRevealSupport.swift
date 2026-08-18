import Foundation

/// Which window owns the keyboard, from the hint system's point of view.
///
/// A window match is only ever used to answer one question: *is a sheet
/// covering the app?* One app window is not one `NSWindow` — full screen puts
/// the toolbar in its own parentless `NSToolbarFullScreenWindow`, so demanding
/// that a badge live in the focused window permanently hides every toolbar
/// hint. Anything that is not a sheet therefore restricts nothing, and
/// `unknown` fails *open*: an app-wide blackout is the worse failure.
/// `foreign` means exactly one thing — another application is frontmost; an
/// unregistered key window of our own (Settings, an alert, a Sparkle prompt)
/// resolves against the most recent host window instead.
enum ShortcutHintFocus: Equatable {
    case host
    case sheet(ObjectIdentifier)
    case unknown
    case foreign

    /// The window badges must belong to, or `nil` when they may show anywhere.
    var restrictedWindowID: ObjectIdentifier? {
        guard case .sheet(let identifier) = self else { return nil }
        return identifier
    }

    var allowsReveal: Bool {
        self != .foreign
    }

    var debugText: String {
        switch self {
        case .host:
            return "host"
        case .sheet:
            return "sheet"
        case .unknown:
            return "unknown"
        case .foreign:
            return "foreign"
        }
    }
}

/// One sample of everything the reveal decision depends on.
///
/// The engine is a pure function of this, so a dropped, reordered or swallowed
/// event costs at most one sampling tick — it can never wedge the feature.
struct ShortcutHintRevealInput: Equatable {
    var modifiers: AppShortcutModifiers
    var focus: ShortcutHintFocus
    var isEnabled: Bool
    var isCaptureActive: Bool
    var timestamp: TimeInterval

    var canReveal: Bool {
        isEnabled && !isCaptureActive && focus.allowsReveal
    }
}

struct ShortcutHintRevealState: Equatable {
    /// When the current Command hold started. `nil` whenever ⌘ is up, so a
    /// missed key-up cannot outlive the next sample.
    var commandDownAt: TimeInterval?
    /// A non-modifier key was pressed during this hold, so it is a chord (⌘N)
    /// rather than a request for hints. Cleared as soon as ⌘ comes back up.
    var isChordInProgress = false

    var isRevealed = false
    var heldModifiers: AppShortcutModifiers = []
    var restrictedWindowID: ObjectIdentifier?
}

enum ShortcutHintRevealEngine {
    /// Re-derives the whole reveal state from a fresh sample. Never trusts
    /// accumulated history beyond the hold clock and the chord flag, both of
    /// which are cleared by the very same sample that sees ⌘ go up.
    static func resolve(
        state: ShortcutHintRevealState,
        input: ShortcutHintRevealInput,
        holdDelay: TimeInterval
    ) -> ShortcutHintRevealState {
        var next = state
        next.heldModifiers = input.modifiers
        next.restrictedWindowID = input.focus.restrictedWindowID

        guard input.modifiers.includesCommandKey else {
            next.commandDownAt = nil
            next.isChordInProgress = false
            next.isRevealed = false
            return next
        }

        let start = next.commandDownAt ?? input.timestamp
        next.commandDownAt = start
        next.isRevealed = input.canReveal
            && !next.isChordInProgress
            && input.timestamp - start >= holdDelay
        return next
    }

    /// A real chord (⌘N) must drop any badge immediately and must not
    /// re-reveal while ⌘ stays down afterwards.
    static func markChord(
        state: inout ShortcutHintRevealState,
        eventModifiers: AppShortcutModifiers
    ) {
        guard eventModifiers.includesCommandKey || state.heldModifiers.includesCommandKey else {
            return
        }
        state.isChordInProgress = true
        state.isRevealed = false
    }

    /// Restarts the hold clock without touching what is on screen. Used when
    /// the app regains focus, so ⌘-Tabbing back in does not count the time
    /// spent in another app as a deliberate hold.
    static func restartHold(state: inout ShortcutHintRevealState) {
        state.commandDownAt = nil
        state.isChordInProgress = false
        state.isRevealed = false
    }
}
