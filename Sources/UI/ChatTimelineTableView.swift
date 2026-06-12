import AppKit
import SwiftUI

// MARK: - Shared per-row inputs

/// Value bundle of everything a single message/streaming/load-earlier cell
/// needs to rebuild its SwiftUI content. Passed wholesale from the
/// representable into the controller on every `apply`, so the controller never
/// reaches back into SwiftUI state.
struct ChatTimelineSharedInputs {
    let maxBubbleWidth: CGFloat
    let columnWidth: CGFloat
    let layoutCenterOffset: CGFloat
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let eagerCodeHighlightStartIndex: Int
    let payloadResolver: RenderedMessagePayloadResolver
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let interaction: ChatMessageInteractionContext
    let onOpenArtifact: (RenderedArtifactVersion) -> Void
    let effectiveRenderMode: (Int, MessageRenderItem) -> MessageRenderMode
    let onExpandCollapsedContent: (UUID) -> Void
    let colorScheme: ColorScheme
}

// MARK: - Row model

/// One row in the recycling timeline. Exactly mirrors the flat child list the
/// pre-rewrite SwiftUI timeline built inside its `LazyVStack`
/// (load-earlier header → messages → streaming → bottom spacer), except the
/// bottom spacer is replaced by the scroll view's bottom content inset.
enum ChatTimelineRow {
    case loadEarlier(hiddenCount: Int, pageSize: Int)
    case message(MessageRenderItem, index: Int)
    case streaming(StreamingMessageState)

    /// Stable identity used both for `ForEach`-style diffing and the height
    /// cache. The streaming row keeps a constant identity for its whole life
    /// so it is reused (and resized in place) as text streams in.
    var identity: String {
        switch self {
        case .loadEarlier:
            return "loadEarlier"
        case .message(let item, _):
            return "msg-\(item.id.uuidString)"
        case .streaming:
            return "streaming"
        }
    }
}

// MARK: - SwiftUI content for a message row

/// Single source of truth for building a `MessageRow` from the shared inputs.
/// The same construction the pre-rewrite SwiftUI timeline used, lifted here so
/// both the (legacy) SwiftUI path and the recycling table render identically.
struct ChatTimelineMessageContent: View {
    let item: MessageRenderItem
    let index: Int
    let shared: ChatTimelineSharedInputs

    var body: some View {
        let interaction = shared.interaction
        let messageEntitiesByID = shared.messageEntitiesByID
        MessageRow(
            item: item,
            maxBubbleWidth: shared.maxBubbleWidth,
            assistantDisplayName: shared.assistantDisplayName,
            providerType: shared.providerType,
            providerIconID: shared.providerIconID,
            deferCodeHighlightUpgrade: index < shared.eagerCodeHighlightStartIndex,
            payloadResolver: shared.payloadResolver,
            toolResultsByCallID: shared.toolResultsByCallID,
            textToSpeechEnabled: interaction.textToSpeechEnabled,
            textToSpeechConfigured: interaction.textToSpeechConfigured,
            textToSpeechIsGenerating: interaction.textToSpeechIsGenerating(item.id),
            textToSpeechIsPlaying: interaction.textToSpeechIsPlaying(item.id),
            textToSpeechIsPaused: interaction.textToSpeechIsPaused(item.id),
            onToggleSpeakAssistantMessage: { messageID, text in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onToggleSpeakAssistantMessage(entity, text)
            },
            onStopSpeakAssistantMessage: { messageID in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onStopSpeakAssistantMessage(entity)
            },
            onRegenerate: { messageID in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onRegenerate(entity)
            },
            onEditUserMessage: { messageID in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onEditUserMessage(entity)
            },
            onDeleteMessage: { messageID in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onDeleteMessage(entity)
            },
            onDeleteResponse: { messageID in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onDeleteResponse(entity)
            },
            onQuoteSelection: interaction.onQuoteSelection,
            onCreateHighlight: interaction.onCreateHighlight,
            onRemoveHighlights: interaction.onRemoveHighlights,
            editingUserMessageID: interaction.editingUserMessageID,
            editingUserMessageText: interaction.editingUserMessageText,
            editingUserMessageFocused: interaction.editingUserMessageFocused,
            onSubmitUserEdit: { messageID in
                guard let entity = messageEntitiesByID[messageID] else { return }
                interaction.onSubmitUserEdit(entity)
            },
            onCancelUserEdit: interaction.onCancelUserEdit,
            editSlashCommand: interaction.editSlashCommand,
            onOpenArtifact: shared.onOpenArtifact,
            renderMode: shared.effectiveRenderMode(index, item),
            onExpandCollapsedContent: shared.onExpandCollapsedContent
        )
        .equatable()
    }
}

/// Wraps any per-row SwiftUI content in the same centered, fixed-column layout
/// the old `ScrollView` applied to the whole stack, plus re-injects the one
/// environment value (`colorScheme`) the message subtree reads from outside its
/// own scope (`CodeBlockView` uses it to pick the syntax theme). A freshly
/// created `NSHostingView` does not inherit the parent SwiftUI environment, so
/// this re-injection is required.
@ViewBuilder
private func chatTimelineCenteredContent<Content: View>(
    _ content: Content,
    shared: ChatTimelineSharedInputs
) -> some View {
    content
        .frame(width: shared.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: shared.layoutCenterOffset)
        .environment(\.colorScheme, shared.colorScheme)
}

// MARK: - Scroll handle (SwiftUI ⇆ controller bridge)

/// Lets the SwiftUI overlay (the "scroll to bottom" chevron) drive the
/// AppKit controller without the controller leaking into the view tree.
@MainActor
final class ChatTimelineScrollHandle: ObservableObject {
    weak var controller: ChatTimelineTableController?

    func scrollToBottom(animated: Bool) {
        controller?.scrollToBottom(animated: animated, force: true)
    }
}

// MARK: - Representable

/// AppKit recycling replacement for the SwiftUI `ScrollView` + `LazyVStack`
/// timeline. A view-based `NSTableView` keeps only the rows whose frames
/// intersect the viewport resident, so the number of live `JinMessageTextView`
/// bridges — the proven linear driver of scroll-frame time — is bounded by the
/// viewport instead of by conversation/message length.
struct ChatTimelineTableRepresentable: NSViewControllerRepresentable {
    let conversationID: UUID
    let rows: [ChatTimelineRow]
    let shared: ChatTimelineSharedInputs
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let streamingModelID: String?
    let topInset: CGFloat
    let bottomInset: CGFloat
    let bottomTolerance: CGFloat
    let nextRenderLimit: Int
    let canLoadEarlier: Bool
    let scrollHandle: ChatTimelineScrollHandle
    @Binding var isPinnedToBottom: Bool
    @Binding var messageRenderLimit: Int
    let onLoadEarlier: () -> Void

    func makeNSViewController(context: Context) -> ChatTimelineTableController {
        let controller = ChatTimelineTableController()
        scrollHandle.controller = controller
        return controller
    }

    func updateNSViewController(_ controller: ChatTimelineTableController, context: Context) {
        scrollHandle.controller = controller
        controller.setStreamingModelInfo(label: streamingModelLabel, id: streamingModelID)
        controller.apply(
            ChatTimelineTableController.Model(
                conversationID: conversationID,
                rows: rows,
                shared: shared,
                streamingMessage: streamingMessage,
                topInset: topInset,
                bottomInset: bottomInset,
                bottomTolerance: bottomTolerance,
                nextRenderLimit: nextRenderLimit,
                canLoadEarlier: canLoadEarlier,
                setPinned: { isPinnedToBottom = $0 },
                setRenderLimit: { messageRenderLimit = $0 },
                onLoadEarlier: onLoadEarlier
            )
        )
    }
}

// MARK: - Reusable hosting cell

/// A recycled cell that hosts one SwiftUI subtree. On reuse the controller
/// swaps `rootView`; the off-screen cells AppKit releases take their resident
/// `NSTextView`s with them — the whole point of the rewrite.
final class ChatTimelineHostingCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ChatTimelineHostingCell")

    let host: NSHostingView<AnyView>

    /// Row identity this cell is currently showing, so a measured-height report
    /// can be matched back to the right row even after recycling.
    var currentIdentity: String?
    /// Called whenever the hosted content's natural height changes (initial
    /// layout, async markdown parse completing, favicons/highlighting loading,
    /// streaming tokens). The controller caches it and re-notes that ONE row.
    var onMeasuredHeight: ((String, CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat = -1
    /// Set on every rootView swap; cleared once `layout()` has forced the
    /// SwiftUI commit. `host.rootView =` only SCHEDULES the view-graph
    /// rebuild, and AppKit layout is top-down (our `layout()` runs before
    /// the host's own), so without the forced flush a recycled cell's first
    /// measurement is the PREVIOUS row's committed content height reported
    /// under the NEW identity — which poisoned the height cache, triggered
    /// ±1000px scroll-anchor fights, and wrote bad heights through to the
    /// warm-start store.
    private var hostHasPendingRootSwap = false

    override init(frame frameRect: NSRect) {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: frameRect)
        // The host fills the cell (leading/trailing fix width = column width;
        // top/bottom make it occupy the row). `.intrinsicContentSize` makes the
        // host expose its content's width-wrapped natural height via
        // `fittingSize`, which we read in `layout()` to drive the row height.
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(identity: String, content: AnyView) {
        currentIdentity = identity
        lastReportedHeight = -1
        host.rootView = content
        hostHasPendingRootSwap = true
        host.invalidateIntrinsicContentSize()
        // Guarantee layout() runs even if AppKit didn't dirty us.
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // `fittingSize` is the content's natural (width-wrapped) height and is
        // independent of our imposed frame, so this reports the TRUE height even
        // while the cell is still sized to a stale estimate. `layout()` re-runs
        // whenever the host invalidates its intrinsic size (async content
        // resolving / streaming), so this catches those without polling.
        guard let identity = currentIdentity else { return }
        if hostHasPendingRootSwap {
            hostHasPendingRootSwap = false
            // NSHostingView commits a pending rootView swap during ITS OWN
            // layout(), which (top-down) runs AFTER ours in this pass — flush
            // it now so `fittingSize` reflects the new content, not the
            // recycled predecessor's. Done here rather than in `configure()`
            // because a dequeued cell may still be windowless there, where
            // hosting-view updates can defer.
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }
        let measured = ceil(host.fittingSize.height)
        guard measured > 0, measured != lastReportedHeight else { return }
        lastReportedHeight = measured
        onMeasuredHeight?(identity, measured)
    }
}

// MARK: - Scroll view (wheel-event hook)

/// `NSScrollView` exposing raw `scrollWheel` events. The live-scroll
/// notifications cover drag gestures and scroller-knob tracking but NOT the
/// momentum phase or single wheel ticks — and the controller's unpin
/// decision must distinguish "the user scrolled" from "layout moved the
/// bounds" (the latter previously mis-unpinned follow-to-bottom during
/// conversation open, leaving it parked above the bottom).
final class ChatTimelineScrollView: NSScrollView {
    var onUserScrollWheel: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onUserScrollWheel?(event)
        super.scrollWheel(with: event)
    }
}

// MARK: - Controller

@MainActor
final class ChatTimelineTableController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    struct Model {
        let conversationID: UUID
        let rows: [ChatTimelineRow]
        let shared: ChatTimelineSharedInputs
        let streamingMessage: StreamingMessageState?
        let topInset: CGFloat
        let bottomInset: CGFloat
        let bottomTolerance: CGFloat
        let nextRenderLimit: Int
        let canLoadEarlier: Bool
        let setPinned: (Bool) -> Void
        let setRenderLimit: (Int) -> Void
        let onLoadEarlier: () -> Void
    }

    private let scrollView = ChatTimelineScrollView()
    private let tableView = NSTableView()

    private var rows: [ChatTimelineRow] = []
    private var model: Model?

    /// Real measured heights, keyed by "rowIdentity|ceil(columnWidth)". Filled
    /// by realized on-screen cells reporting their `fittingSize`; off-screen
    /// rows fall back to `estimatedHeight` so they are NEVER realized to measure.
    private var heightCache: [String: CGFloat] = [:]
    /// Memoized content-aware estimates (same key scheme). The estimator is a
    /// single O(text) pass — fine once, not fine on every `heightOfRow` call.
    private var estimateCache: [String: CGFloat] = [:]

    private var currentColumnWidth: CGFloat = 0
    private var lastConversationID: UUID?

    // Pin / scroll-intent state. These mirror the old SwiftUI machinery:
    // `shouldMaintainBottom` is the latch that keeps follow-to-bottom alive
    // until the user scrolls away; `isProgrammaticScrolling` suppresses the
    // unpin that our own bottom-scrolls would otherwise trigger. Unpin is
    // GESTURE-GATED: only wheel events / live-scroll tracking count as user
    // intent — bounds changes caused by layout (rows re-measuring during
    // open) can no longer disengage follow-to-bottom.
    private var shouldMaintainBottom = true
    private var isProgrammaticScrolling = false
    private var isPinned = true
    private var isUserLiveScrolling = false
    private var lastUserScrollEventAt: TimeInterval = 0

    private var recentUserScrollGesture: Bool {
        isUserLiveScrolling
            || ProcessInfo.processInfo.systemUptime - lastUserScrollEventAt < 0.15
    }

    // MARK: View lifecycle

    override func loadView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        // CRITICAL for recycling: use the `heightOfRow` DELEGATE path, NOT
        // `usesAutomaticRowHeights`. With automatic (Auto-Layout self-sizing)
        // heights the table must REALIZE every row's cell — NSHostingView + all
        // that message's NSTextViews — just to learn its height, so every cell
        // stays resident and scroll cost is linear in conversation length (the
        // exact regression we're fixing). `heightOfRow` returns a NUMBER and
        // never realizes off-screen cells, so only the viewport's cells live.
        // Correct heights still come from the LIVE cell: each realized cell
        // reports its real `fittingSize` height (after async content loads) via
        // `onMeasuredHeight`, which caches it and re-notes that one row.
        tableView.usesAutomaticRowHeights = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsColumnSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = []
        // 16pt vertical gap between rows == the old LazyVStack `spacing: 16`.
        tableView.intercellSpacing = NSSize(width: 0, height: 16)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.scrollerStyle = preferredScrollerStyle()
        scrollView.contentView.postsBoundsChangedNotifications = true
        // The document (table) grows as rows self-size taller (async content
        // resolving, tokens streaming in). Observe that to keep the viewport
        // pinned to the bottom while following a stream.
        tableView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userWillStartLiveScroll),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidEndLiveScroll),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )

        scrollView.onUserScrollWheel = { [weak self] event in
            self?.handleUserScrollWheel(event)
        }

        view = scrollView
    }

    /// The "user scroll wins instantly" guarantee: the very first upward
    /// wheel tick disables follow-to-bottom BEFORE the next streaming
    /// flush's `documentFrameDidChange` could fight the gesture.
    private func handleUserScrollWheel(_ event: NSEvent) {
        lastUserScrollEventAt = ProcessInfo.processInfo.systemUptime
        // `scrollingDeltaY` is already natural-scrolling-adjusted: positive
        // means the content should move down, i.e. the user is scrolling UP
        // toward older messages.
        if event.scrollingDeltaY > 0 {
            shouldMaintainBottom = false
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func preferredScrollerStyle() -> NSScroller.Style {
        let useOverlay = UserDefaults.standard.object(forKey: AppPreferenceKeys.useOverlayScrollbars) as? Bool ?? true
        return useOverlay ? .overlay : NSScroller.preferredScrollerStyle
    }

    // MARK: Apply model

    func apply(_ newModel: Model) {
        let previousRows = rows
        let widthChanged = abs(currentColumnWidth - newModel.shared.columnWidth) > 0.5
        let conversationChanged = lastConversationID != newModel.conversationID

        model = newModel
        rows = newModel.rows
        currentColumnWidth = newModel.shared.columnWidth

        scrollView.scrollerStyle = preferredScrollerStyle()
        let current = scrollView.contentInsets
        if abs(current.top - newModel.topInset) > 0.5 || abs(current.bottom - newModel.bottomInset) > 0.5 {
            scrollView.contentInsets = NSEdgeInsets(top: newModel.topInset, left: 0, bottom: newModel.bottomInset, right: 0)
            // AppKit insets the overlay scroller track by `contentInsets`, so
            // with the composer-sized bottom inset the knob could never reach
            // the bottom of the window even at max scroll. Negative
            // `scrollerInsets` cancel that and restore a full-height track.
            scrollView.scrollerInsets = NSEdgeInsets(top: -newModel.topInset, left: 0, bottom: -newModel.bottomInset, right: 0)
        }

        // Heights are width-dependent (keyed by ceil(columnWidth)); drop the
        // caches on a width change so rows re-measure at the new wrap width.
        if widthChanged {
            heightCache.removeAll(keepingCapacity: true)
            estimateCache.removeAll(keepingCapacity: true)
        }

        if conversationChanged {
            lastConversationID = newModel.conversationID
            shouldMaintainBottom = true
            heightCache.removeAll(keepingCapacity: true)
            estimateCache.removeAll(keepingCapacity: true)
            seedHeightsFromStore()
            reloadDataPreservingPin()
            // Deterministic open-at-bottom: pin once now; every later height
            // correction re-pins via `documentFrameDidChange` for as long as
            // `shouldMaintainBottom` holds — which, with gesture-gated unpin,
            // is "until the user actually scrolls". The previous fixed
            // 0/0.12/0.5s settle timers missed content that measured late
            // (a big code block at the tail) and left the view parked short
            // of the bottom.
            view.layoutSubtreeIfNeeded()
            scrollToBottom(animated: false, force: true)
            return
        }

        reconcile(old: previousRows, new: rows, widthChanged: widthChanged)
    }

    /// `reloadData` + re-note all row heights. On macOS 13.0 the automatic
    /// row-height cache goes stale after `reloadData`; re-noting forces a clean
    /// re-query. (christiantietze.de)
    private func reloadDataPreservingPin() {
        tableView.reloadData()
        // Log AFTER cells have had a chance to realize (reloadData realizes
        // lazily), so the count reflects resident bridges, not zero.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.logResidentTextViewCount("loaded")
        }
        guard !rows.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        }
    }

    /// Diff old→new rows and apply the minimal table mutation, preserving
    /// scroll position (and follow-to-bottom) wherever possible.
    private func reconcile(old: [ChatTimelineRow], new: [ChatTimelineRow], widthChanged: Bool) {
        let oldIDs = old.map(\.identity)
        let newIDs = new.map(\.identity)

        if oldIDs == newIDs {
            // Same rows: a width change (cells re-wrap at the new column width)
            // and/or an in-place content edit. Re-push content into the visible
            // cells (rebuilds with the current shared.columnWidth + new content),
            // which makes them re-self-size, then re-note heights.
            reloadVisibleContent()
            if !new.isEmpty {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<new.count))
            }
            maintainBottomIfNeeded()
            return
        }

        // Same count but some rows differ in place (commonly the streaming row
        // being replaced by the finished message at the same tail index).
        if oldIDs.count == newIDs.count {
            let changed = IndexSet((0..<newIDs.count).filter { oldIDs[$0] != newIDs[$0] })
            if !changed.isEmpty {
                tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
                tableView.noteHeightOfRows(withIndexesChanged: changed)
                maintainBottomIfNeeded()
                return
            }
        }

        // Pure append at the tail (new messages / streaming row appears).
        if newIDs.count > oldIDs.count, Array(newIDs.prefix(oldIDs.count)) == oldIDs {
            let inserted = IndexSet(integersIn: oldIDs.count..<newIDs.count)
            tableView.beginUpdates()
            tableView.insertRows(at: inserted, withAnimation: [])
            tableView.endUpdates()
            maintainBottomIfNeeded()
            return
        }

        // Pure prepend (Load earlier). Preserve the viewport with the canonical
        // capture-then-adjust: record document height + scroll offset BEFORE the
        // insert, then shift the offset by the inserted-height delta AFTER layout
        // resolves. Robust even while the just-inserted rows' heights are still
        // being measured (unlike anchoring on a specific row's rect).
        if newIDs.count > oldIDs.count, Array(newIDs.suffix(oldIDs.count)) == oldIDs {
            let clip = scrollView.contentView
            let oldDocHeight = tableView.frame.height
            let savedOriginY = clip.bounds.origin.y
            let inserted = IndexSet(integersIn: 0..<(newIDs.count - oldIDs.count))
            tableView.beginUpdates()
            tableView.insertRows(at: inserted, withAnimation: [])
            tableView.endUpdates()
            view.layoutSubtreeIfNeeded()
            let delta = tableView.frame.height - oldDocHeight
            isProgrammaticScrolling = true
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: savedOriginY + delta))
            scrollView.reflectScrolledClipView(clip)
            DispatchQueue.main.async { [weak self] in self?.isProgrammaticScrolling = false }
            return
        }

        // General change (deletions, reordering): full reload.
        reloadDataPreservingPin()
        maintainBottomIfNeeded()
    }

    /// Re-pushes SwiftUI content into the cells currently on screen (after a
    /// content edit or a streaming→finished swap at the same index).
    private func reloadVisibleContent() {
        let range = tableView.rows(in: tableView.visibleRect)
        guard range.length > 0 else { return }
        for row in range.location..<(range.location + range.length) where row >= 0 && row < rows.count {
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatTimelineHostingCell {
                cell.configure(identity: rows[row].identity, content: content(for: rows[row]))
            }
        }
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else { return nil }
        let cell = (tableView.makeView(withIdentifier: ChatTimelineHostingCell.identifier, owner: self) as? ChatTimelineHostingCell)
            ?? {
                let created = ChatTimelineHostingCell()
                created.identifier = ChatTimelineHostingCell.identifier
                return created
            }()
        cell.onMeasuredHeight = { [weak self] identity, height in
            self?.cellDidMeasureHeight(identity: identity, height: height)
        }
        cell.configure(identity: rows[row].identity, content: content(for: rows[row]))
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else { return 1 }
        let identity = rows[row].identity
        if let cached = heightCache[heightKey(identity)] { return cached }
        return estimatedHeight(for: rows[row])
    }

    // The table is display-only; no row should be selectable.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    // MARK: Height cache (recycling-preserving)

    private func heightKey(_ identity: String) -> String {
        "\(identity)|\(Int(ceil(max(1, currentColumnWidth))))"
    }

    /// Cheap height for a row we haven't realized yet — a number, so the table
    /// can size the scroller WITHOUT instantiating the cell. The real height
    /// replaces it (via `cellDidMeasureHeight`) when the row scrolls into view.
    /// Content-aware (CJK width, code fences, headings, tables) and memoized:
    /// `heightOfRow` is called repeatedly during scroll for every unmeasured
    /// row, and the previous version re-counted `copyText` (O(n)) per call.
    private func estimatedHeight(for row: ChatTimelineRow) -> CGFloat {
        switch row {
        case .loadEarlier:
            return 56
        case .streaming:
            return 120
        case .message(let item, _):
            let key = heightKey(row.identity)
            if let memoized = estimateCache[key] { return memoized }
            let estimate = ChatTimelineHeightEstimator.estimate(
                text: item.copyText,
                columnWidth: currentColumnWidth
            )
            estimateCache[key] = estimate
            return estimate
        }
    }

    /// A realized cell reported its true natural height (async content has
    /// loaded by now). Cache it, re-note just that one row — and when the
    /// corrected row's top sits ABOVE the viewport, shift the scroll origin
    /// by the same delta so the on-screen content stays pixel-stationary
    /// (the row "grows upward"). Without this, every estimate correction
    /// while scrolling up through history visibly jumped the content.
    private func cellDidMeasureHeight(identity: String, height: CGFloat) {
        let key = heightKey(identity)
        let previous = heightCache[key]
        guard abs((previous ?? -1) - height) > 0.5 else { return }
        heightCache[key] = height
        guard let index = rows.firstIndex(where: { $0.identity == identity }) else {
            // The measurement landed while the row was absent from `rows`
            // (mid-reconcile churn, e.g. the streaming→persisted swap). The
            // cache now holds the right value but nothing would re-query
            // `heightOfRow` until the next reload — in an idle chat that's
            // never, leaving the row clipped at its stale height. Re-note it
            // once the current mutation settles.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let retryIndex = self.rows.firstIndex(where: { $0.identity == identity }) else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    self.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: retryIndex))
                }
                if self.shouldMaintainBottom { self.maintainBottomIfNeeded() }
            }
            return
        }

        if previous == nil {
            logEstimateError(identity: identity, key: key, measured: height)
        }
        storeMeasuredHeight(identity: identity, height: height)

        // Snapshot the CURRENT laid-out geometry — what the table actually
        // shows — before the height change lands. Deltas measured against
        // live geometry compose correctly with load-earlier's
        // capture-then-adjust and with multiple measurements per runloop.
        let clip = scrollView.contentView
        let visibleTop = scrollView.documentVisibleRect.minY
        let oldRowRect = tableView.rect(ofRow: index)
        let delta = height - oldRowRect.height
        let rowTopIsAboveViewport = oldRowRect.minY < visibleTop - 0.5

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
        }

        if shouldMaintainBottom {
            // Pinned: the bottom anchor wins; never also compensate.
            maintainBottomIfNeeded()
            return
        }
        guard rowTopIsAboveViewport, abs(delta) > 0.5 else { return }

        var targetY = clip.bounds.origin.y + delta
        let topLimit = -scrollView.contentInsets.top
        let maxOriginY = tableView.frame.height - clip.bounds.height + scrollView.contentInsets.bottom
        // Clamp inside the legal range so compensation never pops the view
        // into the rubber-band region mid-momentum.
        targetY = min(max(targetY, topLimit), max(topLimit, maxOriginY))
        isProgrammaticScrolling = true
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clip)
        DispatchQueue.main.async { [weak self] in self?.isProgrammaticScrolling = false }
        logAnchorCompensation(row: index, delta: delta)
    }

    /// First-measurement estimate-error telemetry, for tuning
    /// `ChatTimelineHeightEstimator`'s constants against real content.
    private func logEstimateError(identity: String, key: String, measured: CGFloat) {
        guard let estimated = estimateCache[key] else { return }
        ChatDiagnosticLogger.log(
            runId: "scroll-perf",
            hypothesisId: "estimator",
            message: "estimate_error",
            data: [
                "identity": identity,
                "estimated": String(format: "%.0f", estimated),
                "measured": String(format: "%.0f", measured),
                "err": String(format: "%.2f", measured > 0 ? abs(estimated - measured) / measured : 0),
                "width": String(format: "%.0f", currentColumnWidth),
            ]
        )
    }

    private func logAnchorCompensation(row: Int, delta: CGFloat) {
        ChatDiagnosticLogger.log(
            runId: "scroll-perf",
            hypothesisId: "anchor-comp",
            message: "anchor_comp",
            data: [
                "row": String(row),
                "delta": String(format: "%.1f", delta),
            ]
        )
    }

    /// Write-through to the cross-conversation warm-start store.
    private func storeMeasuredHeight(identity: String, height: CGFloat) {
        guard let conversationID = lastConversationID,
              let row = rows.first(where: { $0.identity == identity }),
              case .message(let item, _) = row else { return }
        ChatTimelineRowHeightStore.shared.store(
            height,
            for: ChatTimelineRowHeightStore.Key(
                conversationID: conversationID,
                rowIdentity: identity,
                widthBucket: Int(ceil(max(1, currentColumnWidth))),
                contentSignature: ChatTimelineRowHeightStore.contentSignature(for: item.copyText),
                environmentToken: ChatTimelineRowHeightStore.environmentToken()
            )
        )
    }

    // MARK: Content building

    private func content(for row: ChatTimelineRow) -> AnyView {
        guard let model else { return AnyView(EmptyView()) }
        let shared = model.shared
        switch row {
        case .loadEarlier(let hiddenCount, let pageSize):
            return AnyView(chatTimelineCenteredContent(
                LoadEarlierMessagesRow(
                    hiddenCount: hiddenCount,
                    pageSize: pageSize,
                    onLoad: { [weak self] in self?.handleLoadEarlierTapped() }
                ),
                shared: shared
            ))

        case .message(let item, let index):
            return AnyView(chatTimelineCenteredContent(
                ChatTimelineMessageContent(item: item, index: index, shared: shared),
                shared: shared
            ))

        case .streaming(let state):
            return AnyView(chatTimelineCenteredContent(
                StreamingMessageView(
                    state: state,
                    maxBubbleWidth: shared.maxBubbleWidth,
                    assistantDisplayName: shared.assistantDisplayName,
                    modelLabel: streamingModelLabel,
                    modelID: streamingModelID,
                    providerType: shared.providerType,
                    providerIconID: shared.providerIconID,
                    onContentUpdate: { }
                ),
                shared: shared
            ))
        }
    }

    // The streaming model label/id live on the StreamingMessageView call site
    // in the old code; we thread them through `shared`-adjacent state captured
    // at apply time.
    private var streamingModelLabel: String?
    private var streamingModelID: String?

    private func handleLoadEarlierTapped() {
        guard let model, model.canLoadEarlier else { return }
        model.onLoadEarlier()
        model.setRenderLimit(model.nextRenderLimit)
    }

    func setStreamingModelInfo(label: String?, id: String?) {
        streamingModelLabel = label
        streamingModelID = id
    }

    // NOTE: the streaming row's growth is handled by the same path as every
    // other row — the realized cell's `layout()` re-reports its `fittingSize`
    // as tokens arrive, which re-notes that one row + re-pins. No separate
    // objectWillChange subscription is needed.

    @objc private func documentFrameDidChange() {
        // The table grew/shrank because rows self-sized (async content resolving,
        // streaming tokens). Keep the viewport pinned to the bottom if we're
        // following, but never fight an active user scroll.
        guard shouldMaintainBottom, !isProgrammaticScrolling, !isUserLiveScrolling else { return }
        scrollToBottom(animated: false, force: false)
    }

    // MARK: Pin / follow-to-bottom

    private func distanceFromBottom() -> CGFloat {
        let visible = scrollView.documentVisibleRect
        let docHeight = tableView.frame.height
        return docHeight - visible.maxY
    }

    private func recomputePinned() {
        guard let model else { return }
        let pinned = distanceFromBottom() <= max(0, model.bottomTolerance)
        if pinned != isPinned {
            isPinned = pinned
            model.setPinned(pinned)
        }
    }

    @objc private func boundsDidChange() {
        let distance = distanceFromBottom()
        let tolerance = model.map { max(0, $0.bottomTolerance) } ?? 40
        let pinned = distance <= tolerance
        if pinned != isPinned {
            isPinned = pinned
            model?.setPinned(pinned)
        }
        // Only a USER gesture may change the follow latch. Bounds changes
        // caused by layout (rows re-measuring on open, insets changing) used
        // to be misattributed to the user and disengaged follow-to-bottom.
        guard !isProgrammaticScrolling, recentUserScrollGesture else { return }
        if distance > tolerance {
            shouldMaintainBottom = false
        } else {
            // The user scrolled back to the bottom (including via momentum,
            // which produces no live-scroll notifications) → resume follow.
            shouldMaintainBottom = true
        }
    }

    @objc private func userWillStartLiveScroll() {
        isUserLiveScrolling = true
        if distanceFromBottom() > (model.map { max(0, $0.bottomTolerance) } ?? 40) {
            shouldMaintainBottom = false
        }
    }

    @objc private func userDidEndLiveScroll() {
        isUserLiveScrolling = false
        lastUserScrollEventAt = ProcessInfo.processInfo.systemUptime
        recomputePinned()
        if isPinned { shouldMaintainBottom = true }
        logResidentTextViewCount("scroll-end")
    }

    /// Logs the live JinMessageTextView count (the proven scroll-cost driver) so
    /// we can confirm recycling bounds it without needing the GUI. Gated by the
    /// "Enable Chat Diagnostics" pref; writes to the chat-diagnostics ndjson.
    private func logResidentTextViewCount(_ phase: String) {
        ChatDiagnosticLogger.log(
            runId: "scroll-perf",
            hypothesisId: "recycling",
            message: "resident_textviews",
            data: [
                "phase": phase,
                "liveTextViews": String(JinTextViewCensus.current),
                "rowCount": String(rows.count),
                "visibleRows": String(tableView.rows(in: tableView.visibleRect).length),
            ]
        )
    }

    private func maintainBottomIfNeeded() {
        guard shouldMaintainBottom, !isUserLiveScrolling else { return }
        scrollToBottom(animated: false, force: false)
    }

    func scrollToBottom(animated: Bool, force: Bool) {
        guard force || shouldMaintainBottom else { return }
        guard !rows.isEmpty else { return }
        view.layoutSubtreeIfNeeded()

        let clip = scrollView.contentView
        let docHeight = tableView.frame.height
        let visibleHeight = clip.bounds.height
        let maxOriginY = docHeight - visibleHeight + scrollView.contentInsets.bottom
        let targetY = max(-scrollView.contentInsets.top, maxOriginY)

        if force { shouldMaintainBottom = true }

        isProgrammaticScrolling = true
        let apply = {
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: targetY))
            self.scrollView.reflectScrolledClipView(clip)
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                apply()
            }, completionHandler: { [weak self] in
                // The completion handler runs on the main thread; hop back onto
                // the main actor explicitly to satisfy strict concurrency.
                MainActor.assumeIsolated { self?.finishProgrammaticScroll() }
            })
        } else {
            apply()
            // Let the just-set bounds settle before re-enabling unpin detection.
            DispatchQueue.main.async { [weak self] in self?.finishProgrammaticScroll() }
        }
    }

    private func finishProgrammaticScroll() {
        isProgrammaticScrolling = false
        isPinned = true
        model?.setPinned(true)
    }

    // MARK: Warm-start heights

    /// Pre-seed the local height cache from the cross-conversation store so a
    /// revisited conversation opens with real geometry instead of estimates.
    /// Misses are harmless (estimate path); stale entries can't match — the
    /// key carries width bucket, content signature, and font token.
    private func seedHeightsFromStore() {
        guard let conversationID = lastConversationID else { return }
        let widthBucket = Int(ceil(max(1, currentColumnWidth)))
        let environmentToken = ChatTimelineRowHeightStore.environmentToken()
        for row in rows {
            guard case .message(let item, _) = row else { continue }
            let key = ChatTimelineRowHeightStore.Key(
                conversationID: conversationID,
                rowIdentity: row.identity,
                widthBucket: widthBucket,
                contentSignature: ChatTimelineRowHeightStore.contentSignature(for: item.copyText),
                environmentToken: environmentToken
            )
            if let stored = ChatTimelineRowHeightStore.shared.lookup(key) {
                heightCache[heightKey(row.identity)] = stored
            }
        }
    }

}
