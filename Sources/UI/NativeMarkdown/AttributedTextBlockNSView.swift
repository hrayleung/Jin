import AppKit

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
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForBlockRendering()
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
        layerContentsRedrawPolicy = .onSetNeedsDisplay

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

    // MARK: - Selection

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting, let blockID else { return }
        aggregator?.selectionDidChange(blockID: blockID, localRange: charRange)
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
