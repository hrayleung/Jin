import AppKit
import SwiftUI

/// Process-wide presenter for the LaTeX copy popover.
///
/// One panel at a time — inspecting two formulas simultaneously is not a
/// real interaction, and a singleton means a recycled `NSTextView` / math
/// label cannot leak a popover pointed at a deallocated positioning view.
/// Presentation is on-demand: nothing is allocated until the first click,
/// so the timeline's per-row cost stays zero.
@MainActor
enum LatexSourceCopyPanel {
    private static var popover: NSPopover?
    private static let delegate = Delegate()
    private static weak var positioningView: NSView?
    private static var positioningIdentity: ObjectIdentifier?
    private static var currentSource: String?
    private static var currentPresentation: LatexSourceCopy.PresentationIdentity?
    private static var lastClose: (identity: LatexSourceCopy.PresentationIdentity, at: CFAbsoluteTime)?
    private static var dismissGeneration: UInt64 = 0
    private static var boundsObserver: NSObjectProtocol?
    private static var ignoreNextBoundsChange = false

    static func present(
        source: String,
        relativeTo rect: NSRect,
        of view: NSView,
        charIndex: Int? = nil
    ) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, view.window != nil else { return }

        let identity = LatexSourceCopy.PresentationIdentity.of(view, charIndex: charIndex)
        if LatexSourceCopy.shouldSuppressReopen(
            now: CFAbsoluteTimeGetCurrent(),
            lastClose: lastClose,
            presenting: identity
        ) {
            return
        }

        if let existing = popover, existing.isShown,
           currentPresentation == identity {
            dismiss()
            return
        }

        dismiss()

        let layout = LatexSourceCopy.popoverLayout(for: source)
        let generation = dismissGeneration
        let content = LatexSourceCopyPopoverView(source: source, layout: layout) {
            copyFinished(source: source, generation: generation)
        }
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.view.setFrameSize(layout.size)

        let panel = NSPopover()
        panel.behavior = .semitransient
        panel.animates = true
        panel.delegate = delegate
        panel.contentViewController = hosting
        panel.contentSize = layout.size
        panel.appearance = view.effectiveAppearance

        popover = panel
        positioningView = view
        positioningIdentity = ObjectIdentifier(view)
        currentSource = source
        currentPresentation = identity

        let anchor = rect.width > 0.5 && rect.height > 0.5
            ? rect
            : NSRect(x: rect.midX, y: rect.midY, width: 1, height: 1)
        panel.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        observeScroll(of: view)
    }

    static func dismiss() {
        guard let panel = popover else { return }
        recordCloseIfNeeded()
        clearPresentationState()
        if panel.isShown {
            panel.performClose(nil)
        }
    }

    static func dismissIfPresented(from view: NSView) {
        guard positioningView === view else { return }
        dismiss()
    }

    /// `NSView.deinit` is not `@MainActor`; hop and match by identity so a
    /// recycled cell cannot close a popover that already moved on.
    nonisolated static func dismissDetached(from view: NSView) {
        let id = ObjectIdentifier(view)
        DispatchQueue.main.async {
            dismissIfPositioningIdentity(id)
        }
    }

    static func dismissIfPositioningIdentity(_ id: ObjectIdentifier) {
        guard positioningIdentity == id else { return }
        dismiss()
    }

    fileprivate static func handleDidClose() {
        recordCloseIfNeeded()
        clearPresentationState()
    }

    private static func clearPresentationState() {
        removeBoundsObserver()
        popover = nil
        positioningView = nil
        positioningIdentity = nil
        currentSource = nil
        currentPresentation = nil
        dismissGeneration &+= 1
    }

    /// NSPopover does not follow a positioning view through a scroll. The
    /// timeline is an `NSScrollView`; leaving the panel pinned while the
    /// formula moves is worse than dismissing. `postsBoundsChangedNotifications`
    /// can fire once when enabled, so the first event is ignored.
    private static func observeScroll(of view: NSView) {
        removeBoundsObserver()
        guard let clip = view.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        ignoreNextBoundsChange = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if ignoreNextBoundsChange {
                    ignoreNextBoundsChange = false
                    return
                }
                dismiss()
            }
        }
    }

    private static func removeBoundsObserver() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        ignoreNextBoundsChange = false
    }

    private static func recordCloseIfNeeded() {
        guard let current = currentPresentation else { return }
        lastClose = (current, CFAbsoluteTimeGetCurrent())
    }

    private static func copyFinished(source: String, generation: UInt64) {
        // A later present increments `dismissGeneration`; don't close a panel
        // the user has already replaced with a different formula.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard generation == dismissGeneration, currentSource == source else { return }
            dismiss()
        }
    }

    private final class Delegate: NSObject, NSPopoverDelegate {
        func popoverDidClose(_ notification: Notification) {
            LatexSourceCopyPanel.handleDidClose()
        }
    }
}

// MARK: - Popover content

/// Quiet inspector: a caption + icon copy control, then the complete
/// delimited source wrapped at the measured width. No full-width bezel
/// (that was the gray strip), no second well, no default-button shadow.
private struct LatexSourceCopyPopoverView: View {
    let source: String
    let layout: LatexSourceCopy.PopoverLayout
    let onCopied: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: LatexSourceCopy.PopoverChrome.headerToSource) {
            header
            sourceBlock
        }
        .padding(LatexSourceCopy.PopoverChrome.padding)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("LaTeX")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            copyButton
        }
        .frame(height: LatexSourceCopy.PopoverChrome.headerHeight)
    }

    /// Icon-only. A `Button` whose label contains a `Spacer` becomes a
    /// full-width AppKit default bezel inside `NSPopover` — the gray strip.
    /// No `.keyboardShortcut(.defaultAction)` for the same reason.
    private var copyButton: some View {
        Button(action: copyAll) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(didCopy ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? "Copied" : "Copy LaTeX")
        .accessibilityLabel(didCopy ? "Copied" : "Copy LaTeX")
    }

    @ViewBuilder
    private var sourceBlock: some View {
        // Verbatim so `$…$` is never parsed as markdown. Width is the
        // measured wrap width, using the same NSFont the layout used.
        let text = Text(verbatim: source)
            .font(Font(LatexSourceCopy.PopoverChrome.sourceFont))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .frame(width: layout.sourceWidth, alignment: .leading)
            .textSelection(.enabled)

        Group {
            if layout.sourceNeedsScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    text
                }
            } else {
                text
            }
        }
        .frame(
            width: layout.sourceWidth,
            height: layout.sourceMaxHeight,
            alignment: .topLeading
        )
        .clipped()
        .accessibilityLabel("LaTeX source")
        .accessibilityValue(source)
    }

    private func copyAll() {
        PasteboardSupport.writeString(source)
        didCopy = true
        onCopied()
    }
}
