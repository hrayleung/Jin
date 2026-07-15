import AppKit
import os

/// Process-wide live-instance census for `JinMessageTextView`. Scroll-frame
/// time is linear in the number of RESIDENT text-view bridges, so this is the
/// single most informative perf gauge: if cell recycling works it stays bounded
/// (~viewport worth) while scrolling a long conversation; if recycling is
/// broken it grows with conversation length. Thread-safe (deinit may run
/// off-main) and dependency-free.
enum JinTextViewCensus {
    private static let lock = OSAllocatedUnfairLock(initialState: 0)
    static func increment() { lock.withLock { $0 += 1 } }
    static func decrement() { lock.withLock { $0 -= 1 } }
    static var current: Int { lock.withLock { $0 } }
}

/// Non-scrolling, non-editable `NSTextView` used by every text-bearing block
/// in the native markdown renderer. Self-sizes for the proposed width and,
/// when paired with a `SelectionAggregator`, reports selection changes for
/// quote/highlight UX.
final class JinMessageTextView: NSTextView {

    override var isOpaque: Bool { false }

    /// Identifier used by `SelectionAggregator` to look up this block in
    /// its offset map.
    weak var aggregator: SelectionAggregator?
    var blockID: UUID?

    /// Cache of `(textStorage length, width) -> height` so repeated
    /// `sizeThatFits` probes during a single SwiftUI layout pass don't
    /// re-run `NSLayoutManager.ensureLayout`. Invalidated when the
    /// attributed string is replaced.
    private var cachedHeight: (hash: Int, width: CGFloat, height: CGFloat)?

    func invalidateHeightCache() {
        cachedHeight = nil
    }

    /// Replace U+FFFC (OBJECT REPLACEMENT CHARACTER, the `NSAttachmentCharacter`)
    /// before it reaches the text storage. LLM output occasionally contains a
    /// bare U+FFFC; TextKit 1 classifies it as an attachment control glyph, so
    /// `drawRect:` routes it to `-[NSLayoutManager showAttachment:…]` →
    /// `-[NSView addSubview:]` — adding a subview *during* the layer display
    /// cycle, which mutates the constraint hierarchy and throws
    /// `_postWindowNeedsUpdateConstraints`, crashing the app (and leaving a
    /// mis-laid 1-glyph-wide "ghost" subview / re-throwing every draw pass =
    /// the unusable lag). U+FFFD is a normal printable glyph, so swapping it is
    /// length-preserving (selection/highlight offsets stay aligned) and safe.
    /// The exact (scrubbed) string most recently applied by us. The live
    /// `textStorage` cannot serve as the comparison baseline for the
    /// incremental apply: `processEditing`'s attribute fixing rewrites font
    /// runs (CJK substitution) and the selection aggregator paints highlight
    /// attributes into storage. This is a retain of the (usually
    /// cache-shared) applied instance, not a copy.
    private var lastAppliedSource: NSAttributedString?

    func setScrubbedAttributedString(_ attributed: NSAttributedString) {
        guard let textStorage else { return }
        let scrubbed = Self.scrubbingBareObjectReplacementCharacters(in: attributed)
        textStorage.setAttributedString(scrubbed)
        lastAppliedSource = scrubbed
        // The cache keys on storage LENGTH; a same-length replacement (e.g. a
        // recycled cell whose new message happens to match the old one's
        // UTF-16 count) would otherwise return the previous content's height.
        invalidateHeightCache()
    }

    /// Replace ONLY bare U+FFFC (the crash trigger). A U+FFFC that carries a
    /// real `.attachment` is legitimate — that's how we embed inline math
    /// (see `InlineMath`) — and must be preserved, or the math vanishes.
    /// EVERY path that writes into a `JinMessageTextView`'s text storage must
    /// go through this (full apply and incremental tail append both do).
    static func scrubbingBareObjectReplacementCharacters(
        in attributed: NSAttributedString
    ) -> NSAttributedString {
        guard attributed.string.utf16.contains(0xFFFC) else { return attributed }
        let scrubbed = NSMutableAttributedString(attributedString: attributed)
        let ns = scrubbed.mutableString
        var searchStart = 0
        while searchStart < ns.length {
            let found = ns.range(
                of: "\u{FFFC}",
                options: [],
                range: NSRange(location: searchStart, length: ns.length - searchStart)
            )
            if found.location == NSNotFound { break }
            let hasAttachment = scrubbed.attribute(.attachment, at: found.location, effectiveRange: nil) != nil
            if hasAttachment {
                searchStart = found.location + found.length
            } else {
                scrubbed.replaceCharacters(in: found, with: "\u{FFFD}")
                searchStart = found.location + 1
            }
        }
        return scrubbed
    }

    enum ApplyMode: Equatable {
        case incremental
        case full
    }

    /// Streaming-optimized text apply. When `attributed` is a pure extension
    /// of the current storage — same characters AND same attribute runs over
    /// the existing prefix, which is the common case for a growing streaming
    /// tail — only the new tail is appended, so TextKit relayouts from the
    /// edited paragraph instead of the whole document and the user's
    /// selection survives. Any uncertainty (retro text edit, a late `**`
    /// close restyling earlier characters, aggregator-painted highlight
    /// attributes in storage, shrink/equal length) falls back to the full
    /// `setAttributedString` — exactly the previous behavior.
    @discardableResult
    func applyAttributedStringPreferringIncremental(_ attributed: NSAttributedString) -> ApplyMode {
        guard let textStorage else { return .full }
        guard let baseline = lastAppliedSource,
              baseline.length > 0,
              textStorage.length == baseline.length,
              attributed.length > baseline.length else {
            setScrubbedAttributedString(attributed)
            return .full
        }
        let oldLength = baseline.length

        // Step 1: plain UTF-16 prefix comparison (no copy). The baseline is
        // SCRUBBED — if the new prefix carries a bare U+FFFC the comparison
        // fails against the recorded U+FFFD and we re-scrub fully.
        let newString = attributed.string as NSString
        let prefixMatches = newString.compare(
            baseline.string,
            options: .literal,
            range: NSRange(location: 0, length: oldLength)
        ) == .orderedSame
        guard prefixMatches else {
            setScrubbedAttributedString(attributed)
            return .full
        }

        // Step 2: attribute runs over the prefix must match exactly. Fast in
        // practice: fonts/paragraph styles are process-wide cached singletons
        // and run counts are small.
        guard Self.attributeRunsMatch(baseline, attributed, upTo: oldLength) else {
            setScrubbedAttributedString(attributed)
            return .full
        }

        // Step 3: append only the tail. Storage may carry fixed fonts and
        // painted highlight attributes on the prefix — appending leaves both
        // untouched, which is the point.
        let tail = attributed.attributedSubstring(
            from: NSRange(location: oldLength, length: attributed.length - oldLength)
        )
        let scrubbedTail = Self.scrubbingBareObjectReplacementCharacters(in: tail)
        textStorage.beginEditing()
        textStorage.replaceCharacters(
            in: NSRange(location: oldLength, length: 0),
            with: scrubbedTail
        )
        textStorage.endEditing()
        lastAppliedSource = Self.scrubbingBareObjectReplacementCharacters(in: attributed)
        return .incremental
    }

    private static func attributeRunsMatch(
        _ lhs: NSAttributedString,
        _ rhs: NSAttributedString,
        upTo limit: Int
    ) -> Bool {
        var index = 0
        while index < limit {
            var lhsRange = NSRange()
            var rhsRange = NSRange()
            let clip = NSRange(location: index, length: limit - index)
            let lhsAttrs = lhs.attributes(at: index, longestEffectiveRange: &lhsRange, in: clip)
            let rhsAttrs = rhs.attributes(at: index, longestEffectiveRange: &rhsRange, in: clip)
            guard lhsRange == rhsRange else { return false }
            guard (lhsAttrs as NSDictionary).isEqual(to: rhsAttrs) else { return false }
            index = lhsRange.upperBound
        }
        return true
    }

    init() {
        // NSTextView's designated initializer `init(frame:textContainer:)` does
        // NOT auto-create the text network — Apple's `NSTextView.h` notes that
        // only `init(frame:)` "will create the text network (textStorage,
        // layoutManager, and a container)". Build the TextKit 1 stack manually
        // so `textStorage` / `layoutManager` / `textContainer` are all non-nil
        // — otherwise `textStorage?.setAttributedString(...)` is a silent no-op.
        let storage = NSTextStorage()
        let layoutManager = JinMarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        configureForBlockRendering()
        JinTextViewCensus.increment()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForBlockRendering()
        JinTextViewCensus.increment()
    }

    deinit {
        JinTextViewCensus.decrement()
    }

    /// Customizes the pasteboard write so inline math copies as LaTeX and the
    /// CJK-emphasis-repair ZWSP never leaves the app.
    ///
    /// - No math in the selection: the prior behavior — let AppKit write every
    ///   flavor, then strip U+200B from the plain-text flavor only (RTF keeps
    ///   it; it round-trips invisibly there).
    /// - Math in the selection: each rendered attachment glyph (a single
    ///   U+FFFC, see `InlineMath`) is expanded back to its `.jinInlineMathSource`
    ///   delimited source, and we write ONLY `.string` + `.rtf` from the
    ///   resulting attachment-free string. `.rtfd` and any standalone image
    ///   flavor are deliberately omitted so no receiver — including Jin's own
    ///   plain-text composer, whose paste path would otherwise import the math
    ///   PNG as an image — can resurrect the rendered picture instead of the
    ///   source. Prose styling (bold/links/etc.) survives into the `.rtf`.
    /// Storage and selection offsets are never mutated; the substitution lives
    /// entirely on the outgoing copy.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let textStorage else {
            return super.writeSelection(to: pboard, types: types)
        }
        let ranges = selectedRanges
            .map { $0.rangeValue }
            .filter { $0.length > 0 && NSMaxRange($0) <= textStorage.length }
            .sorted { $0.location < $1.location }
        guard !ranges.isEmpty else {
            return super.writeSelection(to: pboard, types: types)
        }

        let selected = NSMutableAttributedString()
        for range in ranges {
            selected.append(textStorage.attributedSubstring(from: range))
        }

        var hasMath = false
        selected.enumerateAttribute(
            .jinInlineMathSource,
            in: NSRange(location: 0, length: selected.length),
            options: []
        ) { value, _, stop in
            if value is String { hasMath = true; stop.pointee = true }
        }

        guard hasMath else {
            let wrote = super.writeSelection(to: pboard, types: types)
            if wrote,
               let plain = pboard.string(forType: .string),
               plain.contains("\u{200B}") {
                pboard.setString(plain.replacingOccurrences(of: "\u{200B}", with: ""), forType: .string)
            }
            return wrote
        }

        let normalized = Self.latexExpandedAttributedString(from: selected)
        let plain = normalized.string.replacingOccurrences(of: "\u{200B}", with: "")
        let rtfData = normalized.rtf(
            from: NSRange(location: 0, length: normalized.length),
            documentAttributes: [:]
        )

        pboard.clearContents()
        var declared: [NSPasteboard.PasteboardType] = [.string]
        if rtfData != nil { declared.append(.rtf) }
        pboard.declareTypes(declared, owner: nil)
        pboard.setString(plain, forType: .string)
        if let rtfData { pboard.setData(rtfData, forType: .rtf) }
        return true
    }

    /// Returns a copy of `attributed` with every inline-math attachment glyph
    /// (`.jinInlineMathSource`) replaced by a plain text run of its LaTeX
    /// source, inheriting the glyph's text attributes minus the attachment.
    /// Non-math runs pass through verbatim. A coalesced run of N identical
    /// adjacent glyphs (TextKit merges equal `.jinInlineMathSource` values)
    /// expands to its source repeated N times — one per glyph. Shared by the
    /// copy path (this view) and the quote path (`SelectionAggregator`).
    static func latexExpandedAttributedString(from attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.jinInlineMathSource, in: full, options: []) { value, range, _ in
            guard let source = value as? String else {
                result.append(attributed.attributedSubstring(from: range))
                return
            }
            var attrs = attributed.attributes(at: range.location, effectiveRange: nil)
            attrs.removeValue(forKey: .attachment)
            attrs.removeValue(forKey: .jinInlineMathSource)
            let expanded = String(repeating: source, count: max(1, range.length))
            result.append(NSAttributedString(string: expanded, attributes: attrs))
        }
        return result
    }

    /// Plain-string form of `latexExpandedAttributedString`, with the
    /// CJK-repair ZWSP stripped — quotes and prompts must not carry invisible
    /// characters.
    static func latexExpandedPlainString(from attributed: NSAttributedString) -> String {
        latexExpandedAttributedString(from: attributed).string
            .replacingOccurrences(of: "\u{200B}", with: "")
    }

    private func configureForBlockRendering() {
        isEditable = false
        isSelectable = true
        isFieldEditor = false
        isRichText = true
        importsGraphics = false
        allowsImageEditing = false
        drawsBackground = false
        backgroundColor = .clear
        usesFontPanel = false
        usesRuler = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = []
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Layer-back each block so AppKit caches the rasterized text into a
        // CALayer that the scroll view composites on the GPU. Without this
        // every NSTextView in a long conversation has to redraw through
        // drawRect: on each scroll frame — that was the root cause of the
        // post-refactor scroll lag the WebView never had.
        wantsLayer = true
        // `.duringViewResize` re-rasterizes on bounds-SIZE changes — the
        // width-0→real first layout (otherwise a stale 1-glyph-per-line "ghost"
        // raster is cached) and content-height growth — but NOT on pure scroll
        // translation (scrolling moves the view, it doesn't resize it), so the
        // cheap GPU composite scroll path is preserved. This replaces hand-rolled
        // `needsDisplay` bookkeeping that ping-ponged between a ghost raster and
        // a scroll-onset re-raster storm.
        layerContentsRedrawPolicy = .duringViewResize

        // Turn off every "smart" feature NSTextView enables by default.
        // For static, non-editable read-only display of LLM output these
        // are pure overhead: spell/grammar checkers register text-storage
        // observers, link/data detectors run NSDataDetector on every layout
        // pass, Touch Bar item registration multiplies by every view, and
        // the find bar adds menu/responder machinery we never use. None of
        // them are visible because `isEditable = false`, but they all still
        // do work.
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        allowsUndo = false
        usesFindBar = false
        usesFindPanel = false
        usesInspectorBar = false
        displaysLinkToolTips = false
        allowsCharacterPickerTouchBarItem = false
        // Drop default NSTextCheckingType flags so the text checking
        // controller has no work to do.
        enabledTextCheckingTypes = 0
        // We're transparent — declare it on the layer so the compositor
        // doesn't waste opacity work and so we get a sane backing scale.
        layer?.isOpaque = false
    }

    // MARK: - Sizing

    override var intrinsicContentSize: NSSize {
        guard let textContainer else { return super.intrinsicContentSize }
        let width = textContainer.size.width
        if width < 1 {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        // Route through `computeHeight(forWidth:)` so AppKit's repeated reads
        // during scroll/layout hit the (storage-hash, width) cache instead
        // of forcing `ensureLayout` every time.
        return NSSize(width: NSView.noIntrinsicMetric, height: computeHeight(forWidth: width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.size.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        // `widthTracksTextView = true` already keeps the text container in
        // sync. We deliberately do NOT call `invalidateIntrinsicContentSize`
        // or `ensureLayout` here: the previous override created a feedback
        // loop where every frame size set re-armed a layout pass that asked
        // for intrinsic size again. Just drop the cached height so the next
        // `computeHeight` / `intrinsicContentSize` reflects the new width.
        // Re-rasterization on the size change is handled by the layer's
        // `.duringViewResize` policy — no manual `needsDisplay` here (that
        // re-rastered every resident text view at scroll onset).
        if widthChanged {
            invalidateHeightCache()
        }
    }

    /// Lays out the receiver at `width` and returns the text's used height.
    /// Memoized by `(textStorage hash, width)` so repeated probes within a
    /// single SwiftUI layout pass don't re-run NSLayoutManager.
    func computeHeight(forWidth width: CGFloat) -> CGFloat {
        guard let textContainer, let layoutManager else { return 0 }
        let safeWidth = max(1, width)
        let storageHash = textStorage?.length ?? 0
        if let cached = cachedHeight, cached.hash == storageHash, abs(cached.width - safeWidth) < 0.5 {
            return cached.height
        }
        if abs(textContainer.size.width - safeWidth) > 0.5 {
            textContainer.size = NSSize(width: safeWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let height = ceil(used.height)
        cachedHeight = (storageHash, safeWidth, height)
        return height
    }

    func naturalWidth(maxWidth: CGFloat = 10_000) -> CGFloat {
        guard let textContainer, let layoutManager else { return 0 }
        if abs(textContainer.size.width - maxWidth) > 0.5 {
            textContainer.size = NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).width)
    }

    // MARK: - Wheel forwarding (code-block horizontal-scroll trap escape)

    /// Inside a code block this text view sits in a SwiftUI
    /// `ScrollView(.horizontal)` whose backing `NSScrollView` consumes
    /// vertical-dominant wheel events (when the code overflows horizontally)
    /// instead of letting them reach the chat timeline — so the page can't
    /// scroll while the pointer is over code. Intercept here and forward
    /// vertical-dominant events to the enclosing `ChatTimelineScrollView`. For
    /// prose (no horizontal scroll view in the chain) the router resolves the
    /// same timeline the default path would reach, so forwarding is equivalent
    /// — this is safe for every context a `JinMessageTextView` lives in.
    private var wheelRouter = CodeBlockWheelRouter()

    override func scrollWheel(with event: NSEvent) {
        switch wheelRouter.route(event: event, from: self) {
        case .forwardToTimeline(let timeline):
            // Forward the ORIGINAL event so its delta/phase/momentum drive both
            // the timeline's unpin hook and natural momentum animation.
            timeline.scrollWheel(with: event)
        case .passToSuper:
            // Horizontal-dominant (or no timeline): let the code's own
            // horizontal scroll view handle it.
            super.scrollWheel(with: event)
        }
    }

    // MARK: - Selection

    /// Read-only message text must still take focus so selection can be live
    /// (system accent color) and cleared on resign. SwiftUI hosting sometimes
    /// leaves an unfocused `selectedRange` that paints the unemphasized gray
    /// “shadow” permanently.
    override var acceptsFirstResponder: Bool { isSelectable }

    /// Clears residual inactive (gray) selection highlights. Chat messages
    /// host many independent `JinMessageTextView`s (prose groups + table
    /// cells). AppKit keeps `selectedRange` after resign, which paints the
    /// unemphasized selection color — a sticky gray “shadow” that survives
    /// mouse-up / click-away. Clearing here is intentional for read-only
    /// message text: copy/quote still work while first responder; context
    /// menu actions read the aggregator snapshot captured before resign.
    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            clearSelectionHighlightIfNeeded()
        }
        return didResign
    }

    override func mouseDown(with event: NSEvent) {
        // Only one message-text selection at a time. Without this, selecting
        // in cell B leaves cell A's inactive gray highlight behind.
        clearSiblingSelectionsInWindow()
        // Ensure we own first responder before drag-select begins; otherwise
        // AppKit paints unemphasized selection that looks stuck after mouse-up.
        if acceptsFirstResponder, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        // Layer-backed views (`wantsLayer` + `.duringViewResize`) can retain a
        // stale selection raster unless we dirty the view when the range
        // settles (mouse-up) or is cleared.
        if !stillSelecting {
            needsDisplay = true
        }
        guard !stillSelecting, let blockID else { return }
        aggregator?.selectionDidChange(blockID: blockID, localRange: charRange)
    }

    /// Collapse a non-empty selection without moving the viewport.
    func clearSelectionHighlightIfNeeded() {
        let range = selectedRange()
        guard range.length > 0 else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
    }

    private func clearSiblingSelectionsInWindow() {
        guard let root = window?.contentView else { return }
        Self.enumerateJinMessageTextViews(in: root) { other in
            guard other !== self else { return }
            other.clearSelectionHighlightIfNeeded()
        }
    }

    private static func enumerateJinMessageTextViews(in view: NSView, _ body: (JinMessageTextView) -> Void) {
        if let textView = view as? JinMessageTextView {
            body(textView)
        }
        for subview in view.subviews {
            enumerateJinMessageTextViews(in: subview, body)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let aggregator else { return menu }

        if let blockID {
            aggregator.selectionDidChange(blockID: blockID, localRange: selectedRange())
        }

        let hasSelection = aggregator.currentSelectionIsNonEmpty
        let intersectsHighlight = aggregator.currentSelectionIntersectsHighlight

        var customItems: [NSMenuItem] = []
        if hasSelection {
            customItems.append(makeItem(title: "Quote Selection", action: #selector(jinQuoteSelection)))
            customItems.append(makeItem(title: "Highlight", action: #selector(jinHighlightSelection)))
            if intersectsHighlight {
                customItems.append(makeItem(title: "Remove Highlight", action: #selector(jinRemoveHighlight)))
            }
            customItems.append(NSMenuItem.separator())
        }

        for item in customItems.reversed() {
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func jinQuoteSelection(_ sender: Any?) {
        aggregator?.performQuoteFromCurrentSelection()
    }

    @objc private func jinHighlightSelection(_ sender: Any?) {
        aggregator?.performHighlightFromCurrentSelection()
    }

    @objc private func jinRemoveHighlight(_ sender: Any?) {
        aggregator?.performRemoveHighlightsFromCurrentSelection()
    }
}
