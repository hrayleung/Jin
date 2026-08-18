import SwiftUI
#if os(macOS)
import AppKit
#endif

enum ShortcutHintPlacement {
    case above
    case below
    case trailing
    case overlayBottom
}

struct ShortcutHintBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 20, minHeight: 19)
            .padding(.horizontal, label.count > 1 ? 5 : 1)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
            }
            .shadow(color: JinSemanticColor.shadowSubtle, radius: 3, y: 1)
            .compositingGroup()
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ShortcutHintModifier: ViewModifier {
    let action: AppShortcutAction
    let available: Bool
    let placement: ShortcutHintPlacement

    @EnvironmentObject private var shortcutsStore: AppShortcutsStore

    func body(content: Content) -> some View {
        content.modifier(
            ShortcutHintBindingModifier(
                binding: shortcutsStore.binding(for: action),
                available: available,
                placement: placement
            )
        )
    }
}

private struct ShortcutHintBindingModifier: ViewModifier {
    let binding: AppShortcutBinding?
    let available: Bool
    let placement: ShortcutHintPlacement

    @EnvironmentObject private var shortcutHintController: ShortcutHintController
    @AppStorage(AppPreferenceKeys.showShortcutHints) private var showShortcutHints = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowID: ObjectIdentifier?

    func body(content: Content) -> some View {
        content
            .background {
                #if os(macOS)
                ShortcutHintHostWindowReader { window in
                    // Any window holding a badge is by definition one of ours —
                    // including AppKit chrome like the full-screen toolbar
                    // window, which has no parent link back to the main window.
                    shortcutHintController.registerHostWindow(window)
                    let resolvedID = ObjectIdentifier(window)
                    guard windowID != resolvedID else { return }
                    DispatchQueue.main.async {
                        windowID = resolvedID
                    }
                }
                .frame(width: 0, height: 0)
                #endif
            }
            .overlay(alignment: overlayAlignment) {
                if let label {
                    ShortcutHintBadge(label: label)
                        .offset(overlayOffset)
                        .transition(badgeTransition)
                        .zIndex(1)
                }
            }
            .animation(badgeAnimation, value: label)
    }

    private var label: String? {
        guard showShortcutHints, shortcutHintController.isRevealed, available else {
            return nil
        }
        // Fail open. Hide only when we positively know this view sits on a
        // different window than the focused one (a sheet is up, say). An
        // unresolved id on either side must never silence the whole app.
        if let restrictedWindowID = shortcutHintController.restrictedWindowID,
           let windowID,
           restrictedWindowID != windowID {
            return nil
        }
        return ShortcutHintLabelSupport.compactLabel(
            for: binding,
            heldModifiers: shortcutHintController.heldModifiers
        )
    }

    private var overlayAlignment: Alignment {
        placement.overlayAlignment
    }

    private var overlayOffset: CGSize {
        placement.overlayOffset
    }

    private var badgeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom))
    }

    private var badgeAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.12)
    }
}

extension View {
    func shortcutHint(
        _ action: AppShortcutAction?,
        available: Bool = true,
        placement: ShortcutHintPlacement = .above
    ) -> some View {
        modifier(
            OptionalShortcutHintModifier(
                action: action,
                available: available,
                placement: placement
            )
        )
    }

    func fixedShortcutHint(
        _ binding: AppShortcutBinding?,
        available: Bool = true,
        placement: ShortcutHintPlacement = .above
    ) -> some View {
        modifier(
            ShortcutHintBindingModifier(
                binding: binding,
                available: available,
                placement: placement
            )
        )
    }
}

private struct OptionalShortcutHintModifier: ViewModifier {
    let action: AppShortcutAction?
    let available: Bool
    let placement: ShortcutHintPlacement

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.modifier(
                ShortcutHintModifier(
                    action: action,
                    available: available,
                    placement: placement
                )
            )
        } else {
            content
        }
    }
}

private extension ShortcutHintPlacement {
    var overlayAlignment: Alignment {
        switch self {
        case .above:
            return .top
        case .below:
            return .bottom
        case .trailing:
            return .trailing
        case .overlayBottom:
            return .bottom
        }
    }

    var overlayOffset: CGSize {
        switch self {
        case .above:
            return CGSize(width: 0, height: -22)
        case .below:
            return CGSize(width: 0, height: 22)
        case .trailing:
            return CGSize(width: -6, height: 0)
        case .overlayBottom:
            return CGSize(width: 0, height: 6)
        }
    }
}

#if os(macOS)
struct ShortcutHintHostWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HostView else { return }
        view.onResolve = onResolve
        view.reportWindowIfChanged()
    }

    private final class HostView: NSView {
        var onResolve: ((NSWindow) -> Void)?
        private weak var reportedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindowIfChanged()
        }

        /// Fires only when the window actually changes. `updateNSView` runs on
        /// every SwiftUI pass, and reporting from inside one is how observable
        /// state ends up being published mid-update.
        func reportWindowIfChanged() {
            guard let window, window !== reportedWindow else { return }
            reportedWindow = window
            onResolve?(window)
        }
    }
}
#endif
