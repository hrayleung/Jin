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

    /// Cache of `(content version, container width) -> height` so repeated
    /// `sizeThatFits` probes during a single SwiftUI layout pass don't
    /// re-run `NSLayoutManager.ensureLayout`. Keyed by a monotonic version
    /// (NOT the storage length: recycled views see same-length different
    /// content, and highlight upgrades swap attributes without changing a
    /// single character — both must miss). Every storage mutation path calls
    /// `invalidateHeightCache()`, which bumps the version.
    private var cachedHeight: (version: UInt64, width: CGFloat, height: CGFloat)?
    /// Same version-keyed memo for `naturalWidth` — the unconstrained code
    /// path calls it on every `sizeThatFits` probe, and each miss walks
    /// every line fragment after a full `ensureLayout` at ~10,000pt.
    private var cachedNaturalWidth: (version: UInt64, maxWidth: CGFloat, width: CGFloat)?
    private var contentVersion: UInt64 = 0

    func invalidateHeightCache() {
        contentVersion &+= 1
        cachedHeight = nil
        cachedNaturalWidth = nil
    }

    /// The memoized height must include the inset; a late inset change (the
    /// code path sets it after the first string apply) would otherwise keep
    /// serving pre-inset heights.
    override var textContainerInset: NSSize {
        didSet {
            if oldValue != textContainerInset {
                invalidateHeightCache()
            }
        }
    }

    /// The exact (scrubbed) string most recently applied by us. The live
    /// `textStorage` cannot serve as the comparison baseline for the
    /// incremental apply: `processEditing`'s attribute fixing rewrites font
    /// runs (CJK substitution) and the selection aggregator paints highlight
    /// attributes into storage. This is a retain of the (usually
    /// cache-shared) applied instance, not a copy.
    private var lastAppliedSource: NSAttributedString?

    /// Whether `attributed` is already what we applied. Identity first: the
    /// render pipeline hands back cache-shared instances, so the common case
    /// is a pointer compare.
    ///
    /// The comparison MUST be against `lastAppliedSource`, never against the
    /// live `textStorage`: `processEditing` rewrites font runs (CJK
    /// substitution) and the aggregator paints highlight attributes into
    /// storage, so storage never equals the source again after the first
    /// apply. Comparing against storage answered "not applied yet" forever,
    /// which made every single `sizeThatFits` treat the content as pending —
    /// measured at 491 full-text copies + re-layouts across 40 scroll steps.
    ///
    /// `lastAppliedSource` is the SCRUBBED string, so content carrying a bare
    /// U+FFFC has to be scrubbed before the comparison or it too would read as
    /// pending forever — the same never-matching trap, just narrower. The
    /// scrub is identity-returning when there is nothing to replace, so the
    /// common case stays a pointer compare.
    func hasAppliedSource(_ attributed: NSAttributedString) -> Bool {
        guard let lastAppliedSource else { return false }
        if lastAppliedSource === attributed { return true }
        return lastAppliedSource.isEqual(
            to: Self.scrubbingBareObjectReplacementCharacters(in: attributed)
        )
    }

    // MARK: - Storage-mutation reentrancy guard

    /// Single-click candidate for the inline-math copy popover. Set in
    /// `mouseDown` only when the press is unmodified, clickCount == 1, and
    /// lands inside a `.jinInlineMathSource` glyph; cleared on drag-past-slop
    /// or `mouseUp`. Nil-cost when the user is selecting prose.
    private var latexClickCandidate: LatexSourceCopy.ClickCandidate?

    /// Depth of text-storage edits this view is currently performing.
    ///
    /// A storage edit is NOT a leaf operation. `endEditing` fans the change
    /// out to the layout managers; the live one fixes up the text view's
    /// selection; `-[NSTextView setSelectedRanges:affinity:stillSelecting:]`
    /// posts an accessibility notification. When anything is observing
    /// accessibility, AppKit services that notification synchronously, which
    /// re-enters SwiftUI's view graph and lands back in either
    /// `AttributedTextBlock.updateNSView` (a second apply, nested inside the
    /// first edit's fan-out) or `AttributedTextBlock.sizeThatFits` (a
    /// measurement against layout managers that have not been told about the
    /// edit yet). Both corrupt TextKit; the second is the build-658 crash.
    private var storageMutationDepth = 0

    /// True while this view is inside one of its own text-storage edits. No
    /// layout manager attached to this storage may be driven while it is set,
    /// and no second edit may start.
    var isMutatingTextStorage: Bool { storageMutationDepth > 0 }

    /// Work that arrived while an edit was already in flight, replayed when
    /// the outermost edit unwinds — deferred, never dropped.
    private var deferredApplySource: NSAttributedString?
    private var deferredStorageMutations: [(NSTextStorage) -> Void] = []
    private var servedMeasurementDuringMutation = false
    private var isDrainingDeferredWork = false

    private var hasDeferredWork: Bool {
        deferredApplySource != nil || !deferredStorageMutations.isEmpty || servedMeasurementDuringMutation
    }

    private func withStorageMutation(_ body: () -> Void) {
        storageMutationDepth += 1
        defer {
            storageMutationDepth -= 1
            if storageMutationDepth == 0, hasDeferredWork { drainDeferredWork() }
        }
        body()
    }

    /// Replays whatever the reentrancy guard turned away, then makes the owner
    /// re-read the size: anything measured during the window was answered off
    /// the isolated stack and deliberately not memoized.
    private func drainDeferredWork() {
        guard !isDrainingDeferredWork else { return }
        isDrainingDeferredWork = true
        defer { isDrainingDeferredWork = false }
        servedMeasurementDuringMutation = false
        // Each replay writes for real, so this terminates on anything short of
        // a source that keeps generating new content from inside every edit.
        // Capped anyway: a livelock here would be a beachball.
        var replays = 0
        while deferredApplySource != nil || !deferredStorageMutations.isEmpty, replays < 4 {
            replays += 1
            if let pending = deferredApplySource {
                deferredApplySource = nil
                applyAttributedStringPreferringIncremental(pending)
            }
            let mutations = deferredStorageMutations
            deferredStorageMutations = []
            for mutation in mutations { performStorageMutation(mutation) }
        }
        if deferredApplySource != nil || !deferredStorageMutations.isEmpty {
            // Hitting the cap must not silently strand the newest content: a
            // dropped apply leaves the row showing text the model already
            // replaced, and `AttributedTextBlock` has recorded the signature
            // so nothing would ask again. Land it on the next turn of the run
            // loop instead, where no edit can be in flight.
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(drainDeferredWorkOnNextRunLoopTurn),
                object: nil
            )
            perform(
                #selector(drainDeferredWorkOnNextRunLoopTurn),
                with: nil,
                afterDelay: 0,
                inModes: [.common]
            )
        }
        invalidateIntrinsicContentSize()
    }

    @objc private func drainDeferredWorkOnNextRunLoopTurn() {
        guard hasDeferredWork else { return }
        drainDeferredWork()
    }

    /// Entry point for code outside this class that needs to edit this view's
    /// text storage (the selection aggregator paints highlight attributes).
    /// Routing through here puts those edits under the same reentrancy guard
    /// the content applies use.
    func performStorageMutation(_ body: @escaping (NSTextStorage) -> Void) {
        guard let textStorage else { return }
        guard !isMutatingTextStorage else {
            deferredStorageMutations.append(body)
            return
        }
        withStorageMutation { body(textStorage) }
    }

    func setScrubbedAttributedString(_ attributed: NSAttributedString) {
        guard let textStorage else { return }
        let scrubbed = Self.scrubbingBareObjectReplacementCharacters(in: attributed)
        guard !isMutatingTextStorage else {
            deferredApplySource = scrubbed
            return
        }
        // Baseline and memo are updated BEFORE the write, not after: the write
        // re-enters us (see `storageMutationDepth`), and a stale baseline there
        // answers "not applied yet", which starts a second edit nested inside
        // this one's notification fan-out.
        lastAppliedSource = scrubbed
        invalidateHeightCache()
        LatexSourceCopyPanel.dismissIfPresented(from: self)
        withStorageMutation {
            textStorage.setAttributedString(scrubbed)
        }
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
        /// The apply arrived while a storage edit was already in flight and
        /// was queued for replay when that edit unwinds — see
        /// `storageMutationDepth`. Nothing was written yet.
        case deferred
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
        guard !isMutatingTextStorage else {
            deferredApplySource = attributed
            return .deferred
        }
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
        // Baseline and memo before the write, same as the full apply and for
        // the same reason: `endEditing` below re-enters us.
        lastAppliedSource = Self.scrubbingBareObjectReplacementCharacters(in: attributed)
        // The version key doesn't observe storage edits — every mutation
        // path invalidates explicitly, including this one.
        invalidateHeightCache()
        withStorageMutation {
            textStorage.beginEditing()
            textStorage.replaceCharacters(
                in: NSRange(location: oldLength, length: 0),
                with: scrubbedTail
            )
            textStorage.endEditing()
        }
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
        LatexSourceCopyPanel.dismissDetached(from: self)
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
    /// expands to its source repeated N times — one per glyph.
    ///
    /// Parse-failure fallbacks are the same attribute on the already-visible
    /// `$…$` characters (no attachment). Those runs must be preserved as-is;
    /// repeating `source` `range.length` times would duplicate the formula
    /// once per UTF-16 unit on copy/quote. Shared by the copy path (this view)
    /// and the quote path (`SelectionAggregator`).
    static func latexExpandedAttributedString(from attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.jinInlineMathSource, in: full, options: []) { value, range, _ in
            guard let source = value as? String else {
                result.append(attributed.attributedSubstring(from: range))
                return
            }
            let hasAttachment = attributed.attribute(
                .attachment,
                at: range.location,
                effectiveRange: nil
            ) != nil
            if hasAttachment {
                var attrs = attributed.attributes(at: range.location, effectiveRange: nil)
                attrs.removeValue(forKey: .attachment)
                attrs.removeValue(forKey: .jinInlineMathSource)
                let expanded = String(repeating: source, count: max(1, range.length))
                result.append(NSAttributedString(string: expanded, attributes: attrs))
            } else {
                let slice = NSMutableAttributedString(
                    attributedString: attributed.attributedSubstring(from: range)
                )
                slice.removeAttribute(
                    .jinInlineMathSource,
                    range: NSRange(location: 0, length: slice.length)
                )
                result.append(slice)
            }
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
        let containerWidth = textContainer.size.width
        if containerWidth < 1 {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        // Route through `computeHeight(forWidth:)` so AppKit's repeated reads
        // during scroll/layout hit the (version, width) cache instead of
        // forcing `ensureLayout` every time. `computeHeight` takes a VIEW
        // width; the tracked container is already inset-shrunk, so add the
        // inset back for an exact round-trip.
        let viewWidth = containerWidth + textContainerInset.width * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: computeHeight(forWidth: viewWidth))
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

    /// Lays out the receiver at VIEW width `width` and returns the height the
    /// view needs to show all of it — text plus `textContainerInset` on both
    /// axes, wrapping at the same container width render will use. The
    /// previous version measured the bare `usedRect` at the full view width:
    /// for inset views (code blocks: inset (14, 10)) that under-reported the
    /// height by 20pt AND wrapped 28pt wider than the render pass — both
    /// resolved as content clipped at the row's bottom mask. Memoized by
    /// `(content version, view width)`.
    ///
    /// The measurement must be SIDE-EFFECT-FREE. SwiftUI probes
    /// `sizeThatFits` at min/ideal/max widths, and those probes run INSIDE
    /// AppKit's layout/constraint cycle, so any width other than the live one
    /// is measured on a SHADOW layout manager. Three designs shipped
    /// crashes/corruption before this one: driving the view's own frame
    /// re-wrapped the on-screen text at whichever probe width came last (text
    /// painted past its card, mid-line clips); resizing the live
    /// `textContainer` invalidated the live layout manager mid-cycle — the
    /// later `ensureLayout` in the same cycle then walked a layout hole past
    /// the storage end and threw `-[NSRLEArray objectAtRunIndex:length:]` out
    /// of bounds; and measuring on ANY manager of this storage while an edit
    /// was still fanning out threw from
    /// `-[NSLayoutManager _fillGlyphHoleForCharacterRange:…]`. Hence
    /// `canDriveLayoutManagers`, which routes those moments to the isolated
    /// `JinTextMeasurementStack` instead.
    func computeHeight(forWidth width: CGFloat) -> CGFloat {
        guard let textContainer, let layoutManager else { return 0 }
        let inset = textContainerInset
        let safeWidth = max(1, width)
        if let cached = cachedHeight, cached.version == contentVersion, abs(cached.width - safeWidth) < 0.5 {
            return cached.height
        }
        let containerWidth = max(1, safeWidth - inset.width * 2)
        guard canDriveLayoutManagers else {
            return midEditHeight(containerWidth: containerWidth, inset: inset)
        }
        let height: CGFloat
        if abs(textContainer.size.width - containerWidth) <= 0.5 {
            // Live width — measure in place (steady-state path, and the only
            // one `intrinsicContentSize` ever takes).
            layoutManager.ensureLayout(for: textContainer)
            JinLayoutCostCounters.liveMeasureLayouts += 1
            height = ceil(layoutManager.usedRect(for: textContainer).height + inset.height * 2)
        } else if let shadow = shadowContainer(for: containerWidth) {
            height = ceil(shadow.manager.usedRect(for: shadow.container).height + inset.height * 2)
        } else {
            return midEditHeight(containerWidth: containerWidth, inset: inset)
        }
        cachedHeight = (contentVersion, safeWidth, height)
        return height
    }

    /// Unwrapped natural VIEW width: text laid out inside `maxWidth` minus
    /// the horizontal insets, reported with the insets added back — so the
    /// frame SwiftUI derives from it gives render the same container width
    /// measured here. Same side-effect-free probing as
    /// `computeHeight(forWidth:)`.
    ///
    /// Width comes from a per-line `lineFragmentUsedRect` scan, NOT the
    /// aggregate `usedRect`: after a manual container resize TextKit 1
    /// reports the aggregate's WIDTH as the full container width (measured
    /// 9972 for a 152pt single line) while the per-fragment used rects stay
    /// truthful. Heights are unaffected by this quirk.
    func naturalWidth(maxWidth: CGFloat = 10_000) -> CGFloat {
        guard let textContainer, let layoutManager else { return 0 }
        let inset = textContainerInset
        let safeMaxWidth = max(1, maxWidth)
        if let cached = cachedNaturalWidth, cached.version == contentVersion,
           abs(cached.maxWidth - safeMaxWidth) < 0.5 {
            return cached.width
        }
        let containerWidth = max(1, safeMaxWidth - inset.width * 2)
        guard canDriveLayoutManagers else {
            return midEditNaturalWidth(containerWidth: containerWidth, inset: inset)
        }
        let width: CGFloat
        if abs(textContainer.size.width - containerWidth) <= 0.5 {
            layoutManager.ensureLayout(for: textContainer)
            width = ceil(layoutManager.jinWidestLineFragmentRight(in: textContainer) + inset.width * 2)
        } else if let shadow = shadowContainer(for: containerWidth) {
            width = ceil(shadow.manager.jinWidestLineFragmentRight(in: shadow.container) + inset.width * 2)
        } else {
            return midEditNaturalWidth(containerWidth: containerWidth, inset: inset)
        }
        cachedNaturalWidth = (contentVersion, safeMaxWidth, width)
        return width
    }

    // MARK: Mid-edit measuring

    /// Whether ANY layout manager attached to this view's text storage may be
    /// driven right now — `ensureLayout`, `usedRect`, or even
    /// `addLayoutManager`.
    ///
    /// Answering yes at the wrong moment is the build-658 production crash.
    /// TextKit states the rule itself, in the exception it raises:
    ///
    ///     -[NSLayoutManager _fillGlyphHoleForCharacterRange:startGlyphIndex:
    ///     desiredNumberOfCharacters:] *** attempted glyph generation while
    ///     textStorage is editing. It is not valid to cause the layoutManager
    ///     to do glyph generation while the textStorage is editing
    ///
    /// It is uncatchable inside AppKit's constraint pass, so it kills the app.
    /// Three independent nets, because the app is re-entered here from AppKit
    /// (an accessibility notification posted by the layout manager's post-edit
    /// `setSelectedRange:`) and none of the three sees every case:
    ///
    ///  - `editedMask` — AppKit's own "there are pending changes" flag, and
    ///    the closest thing to the condition named in the exception. Set for
    ///    the whole of `processEditing`, i.e. the entire fan-out to the layout
    ///    managers, and set for edits nobody in this file made — including
    ///    attribute-only ones, which the length check below cannot see.
    ///  - `storageMutationDepth` — our own edits, including the window between
    ///    `beginEditing()` and the first change, where `editedMask` is still
    ///    empty but the storage is already refusing glyph generation.
    ///  - `jinIsStaleRelativeToStorage` — a manager that has not been notified
    ///    yet. The storage notifies its managers one at a time in the order
    ///    they were added, so on re-entry from inside the LIVE manager's
    ///    callback the shadow one is still describing the previous text.
    private var canDriveLayoutManagers: Bool {
        if isMutatingTextStorage { return false }
        if let textStorage, !textStorage.editedMask.isEmpty { return false }
        if let live = layoutManager as? JinMarkdownLayoutManager, live.jinIsStaleRelativeToStorage {
            return false
        }
        if let shadow = shadowLayoutManager, shadow.jinIsStaleRelativeToStorage { return false }
        return true
    }

    /// Stable identity for this view's slot in the isolated measuring stack.
    private lazy var measurementStackKey = "view:\(UInt(bitPattern: ObjectIdentifier(self).hashValue))"

    /// Height for a width that cannot be measured on this storage's managers.
    ///
    /// `JinTextMeasurementStack` owns a text storage nobody else touches, so
    /// it is unaffected by whatever edit is in flight here. It measures
    /// `lastAppliedSource` — the string we most recently decided to show,
    /// which the apply paths record BEFORE writing it — so the answer is the
    /// height of the content that is landing, not of the content it replaced.
    /// Costs one string copy, and only in this window; the steady-state paths
    /// above are untouched.
    private func midEditHeight(containerWidth: CGFloat, inset: NSSize) -> CGFloat {
        noteMidEditMeasurement()
        guard let source = lastAppliedSource else {
            return cachedHeight?.height ?? max(0, frame.height)
        }
        return ceil(
            JinTextMeasurementStack.height(
                of: source,
                token: JinTextMeasurementStack.Token(key: measurementStackKey, version: contentVersion),
                containerWidth: containerWidth
            ) + inset.height * 2
        )
    }

    private func midEditNaturalWidth(containerWidth: CGFloat, inset: NSSize) -> CGFloat {
        noteMidEditMeasurement()
        guard let source = lastAppliedSource else {
            return cachedNaturalWidth?.width ?? 0
        }
        return ceil(
            JinTextMeasurementStack.maxLineRight(
                of: source,
                token: JinTextMeasurementStack.Token(key: measurementStackKey, version: contentVersion),
                containerWidth: containerWidth
            ) + inset.width * 2
        )
    }

    /// Mid-edit answers are deliberately NOT memoized (the version key still
    /// belongs to the edit in flight). Remember that one was served so the
    /// unwinding edit re-invalidates the intrinsic size and the owner asks
    /// again from the normal path.
    ///
    /// Also logged, throttled: this path firing in a shipped build means
    /// something is re-entering layout from inside a text-storage edit, which
    /// is the shape of the crash. It is now survivable, but the next
    /// investigation should not have to guess whether it happened.
    private func noteMidEditMeasurement() {
        JinLayoutCostCounters.midEditMeasurements += 1
        if isMutatingTextStorage { servedMeasurementDuringMutation = true }
        let count = JinLayoutCostCounters.midEditMeasurements
        guard count <= 5 || count % 500 == 0 else { return }
        ChatDiagnosticLogger.log(
            runId: "textkit-reentrancy",
            hypothesisId: "midEditMeasurement",
            message: "sizing_probe_inside_storage_edit",
            data: [
                "count": String(count),
                "ownEdit": String(isMutatingTextStorage),
                "storageEditing": String(textStorage.map { !$0.editedMask.isEmpty } ?? false),
            ]
        )
    }

    // MARK: Shadow measuring stack

    /// A SECOND `NSLayoutManager` over this view's OWN text storage, used for
    /// every width other than the one the view is currently rendering at.
    ///
    /// TextKit 1 supports several layout managers per storage, each with its
    /// own containers, so resizing THIS container cannot disturb the live one
    /// — which is the whole requirement: `sizeThatFits` runs inside AppKit's
    /// layout cycle, where touching the live layout manager's inputs corrupts
    /// it (see `computeHeight(forWidth:)`).
    ///
    /// Sharing the storage is what makes it cheap. A process-wide measuring
    /// stack had to `setAttributedString` a full COPY of the text whenever the
    /// probe moved to a different block, which during a scroll means copying
    /// and re-laying-out the visible conversation over and over: measured at
    /// 809 copies / 936 layouts across 40 scroll steps (~68ms per step). Here
    /// there is no copy at all, and the shadow keeps its glyphs between
    /// probes. Created lazily — a view that is only ever measured at its
    /// render width never pays for one.
    private var shadowLayoutManager: JinMarkdownLayoutManager?
    private var shadowTextContainer: NSTextContainer?

    private func shadowContainer(
        for containerWidth: CGFloat
    ) -> (manager: NSLayoutManager, container: NSTextContainer)? {
        guard let textStorage else { return nil }
        // Both callers check this already; repeated here because the cost of
        // getting it wrong is not a wrong number but a crash — `ensureLayout`
        // below is the frame that threw in production, and on the first probe
        // this function also calls `addLayoutManager`, which mutates the very
        // array `NSTextStorage` is iterating during an edit fan-out.
        guard canDriveLayoutManagers else { return nil }
        let manager: JinMarkdownLayoutManager
        let container: NSTextContainer
        if let existingManager = shadowLayoutManager, let existingContainer = shadowTextContainer {
            manager = existingManager
            container = existingContainer
        } else {
            manager = JinMarkdownLayoutManager()
            container = NSTextContainer(
                size: NSSize(width: max(1, containerWidth), height: CGFloat.greatestFiniteMagnitude)
            )
            container.lineFragmentPadding = 0
            // Never attached to a view: only we drive this width.
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            manager.addTextContainer(container)
            textStorage.addLayoutManager(manager)
            shadowLayoutManager = manager
            shadowTextContainer = container
        }
        if abs(container.size.width - containerWidth) > 0.5 {
            container.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        manager.ensureLayout(for: container)
        JinLayoutCostCounters.shadowLayouts += 1
        return (manager, container)
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

    /// Code blocks set a 14pt leading `textContainerInset`. `NSTextView` on
    /// some AppKit versions (GitHub-hosted macOS 15 / Xcode 26) returns `nil`
    /// for points in that padding, so the SwiftUI `DocumentView` behind the
    /// text eats vertical wheels. Claim every in-bounds pixel; prose uses a
    /// zero inset so this is a no-op there.
    override func hitTest(_ point: NSPoint) -> NSView? {
        CodeBlockHitTesting.hitTest(self, pointInSuperview: point, superHit: super.hitTest(point))
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            LatexSourceCopyPanel.dismissIfPresented(from: self)
        }
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
        if event.clickCount > 1 {
            latexClickCandidate = nil
            LatexSourceCopyPanel.dismissIfPresented(from: self)
            super.mouseDown(with: event)
            return
        }
        latexClickCandidate = LatexSourceCopy.clickCandidate(
            event: event,
            hit: latexHit(at: convert(event.locationInWindow, from: nil))
        )
        // A math click must not start a text selection — that was why some
        // formulas only "copied" via drag-select and never opened the panel.
        // Drag-select still works when the press is on prose.
        if latexClickCandidate == nil {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let candidate = latexClickCandidate {
            let dist = LatexSourceCopy.dragDistanceSquared(
                from: candidate.downPointInWindow,
                to: event.locationInWindow
            )
            if dist > LatexSourceCopy.clickSlop * LatexSourceCopy.clickSlop {
                latexClickCandidate = nil
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let candidate = latexClickCandidate
        latexClickCandidate = nil
        super.mouseUp(with: event)
        guard let candidate else { return }
        let dist = LatexSourceCopy.dragDistanceSquared(
            from: candidate.downPointInWindow,
            to: event.locationInWindow
        )
        guard LatexSourceCopy.isClick(
            dragDistanceSquared: dist,
            clickCount: event.clickCount,
            modifierFlags: event.modifierFlags
        ) else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = latexHit(at: point), hit.charIndex == candidate.charIndex else { return }
        clearSelectionHighlightIfNeeded()
        LatexSourceCopyPanel.present(
            source: hit.source,
            relativeTo: hit.rectInView,
            of: self,
            charIndex: hit.charIndex
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if latexHit(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    /// Cheap, layout-only. Skipped during a storage mutation because the
    /// layout manager may not have been notified of the edit yet.
    private func latexHit(at point: NSPoint) -> LatexSourceCopy.Hit? {
        guard !isMutatingTextStorage else { return nil }
        return LatexSourceCopy.inlineMathHit(at: point, in: self)
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

        let point = convert(event.locationInWindow, from: nil)
        if let hit = latexHit(at: point) {
            let item = NSMenuItem(title: "Copy LaTeX", action: #selector(jinCopyInlineLatex(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = hit.source
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }

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

        // Copy LaTeX (if any) is already at 0; insert quote/highlight after it
        // so the math action stays the first item when the click is on a formula.
        let insertionIndex = menu.items.first?.title == "Copy LaTeX" ? 2 : 0
        for item in customItems.reversed() {
            menu.insertItem(item, at: min(insertionIndex, menu.items.count))
        }
        return menu
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func jinCopyInlineLatex(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? String, !source.isEmpty else { return }
        PasteboardSupport.writeString(source)
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
