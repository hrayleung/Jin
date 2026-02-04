import SwiftUI
import AppKit

/// AppKit-backed chat message list for extreme scrolling performance.
///
/// Motivation: SwiftUI `ScrollView` + `LazyVStack` can become janky for long, dynamic-height histories,
/// especially with frequent streaming updates. `NSTableView` provides view reuse and mature scrolling.
struct AppKitChatMessagesView: NSViewRepresentable {
    let conversationID: UUID
    let messages: [MessageEntity]
    let messagesVersion: Int

    let streamingMessage: StreamingMessageState?

    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let assistantIcon: String?
    let toolResultsByCallID: [String: ToolResult]
    let toolResultsVersion: Int
    let isRerunAllowed: Bool
    let rerunningToolCallIDs: Set<String>
    let onRerunToolCall: (ToolCall) -> Void

    let contentInsets: NSEdgeInsets
    let backgroundColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(
            conversationID: conversationID,
            messages: messages,
            messagesVersion: messagesVersion,
            streamingMessage: streamingMessage,
            maxBubbleWidth: maxBubbleWidth,
            assistantDisplayName: assistantDisplayName,
            assistantIcon: assistantIcon,
            toolResultsByCallID: toolResultsByCallID,
            toolResultsVersion: toolResultsVersion,
            isRerunAllowed: isRerunAllowed,
            rerunningToolCallIDs: rerunningToolCallIDs,
            onRerunToolCall: onRerunToolCall
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.usesAutomaticRowHeights = true
        tableView.rowHeight = 44

        let column = NSTableColumn(identifier: Coordinator.columnID)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = contentInsets

        context.coordinator.attach(tableView: tableView, scrollView: scrollView)
        tableView.reloadData()

        // First render should start at the bottom of the conversation.
        DispatchQueue.main.async {
            context.coordinator.scrollToBottom(force: true)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.backgroundColor = backgroundColor
        nsView.automaticallyAdjustsContentInsets = false
        nsView.contentInsets = contentInsets

        context.coordinator.applyUpdate(
            conversationID: conversationID,
            messages: messages,
            messagesVersion: messagesVersion,
            streamingMessage: streamingMessage,
            maxBubbleWidth: maxBubbleWidth,
            assistantDisplayName: assistantDisplayName,
            assistantIcon: assistantIcon,
            toolResultsByCallID: toolResultsByCallID,
            toolResultsVersion: toolResultsVersion,
            isRerunAllowed: isRerunAllowed,
            rerunningToolCallIDs: rerunningToolCallIDs,
            onRerunToolCall: onRerunToolCall
        )
    }
}

extension AppKitChatMessagesView {
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columnID = NSUserInterfaceItemIdentifier("main")
        private static let cellID = NSUserInterfaceItemIdentifier("ChatRowCell")

        private weak var tableView: NSTableView?
        private weak var scrollView: NSScrollView?

        private var conversationID: UUID

        private var messages: [MessageEntity]
        private var messagesVersion: Int
        private var streamingMessage: StreamingMessageState?

        private var maxBubbleWidth: CGFloat
        private var assistantDisplayName: String
        private var assistantIcon: String?
        private var toolResultsByCallID: [String: ToolResult]
        private var toolResultsVersion: Int
        private var isRerunAllowed: Bool
        private var rerunningToolCallIDs: Set<String>
        private var onRerunToolCall: (ToolCall) -> Void

        private var isPinnedToBottom = true
        private var lastColumnWidth: CGFloat = 0

        private var lastAutoScrollUptime: TimeInterval = 0
        private var pendingStreamingHeightUpdate: DispatchWorkItem?
        private var lastStreamingHeightUpdateUptime: TimeInterval = 0

        private var clipBoundsObserver: NSObjectProtocol?

        init(
            conversationID: UUID,
            messages: [MessageEntity],
            messagesVersion: Int,
            streamingMessage: StreamingMessageState?,
            maxBubbleWidth: CGFloat,
            assistantDisplayName: String,
            assistantIcon: String?,
            toolResultsByCallID: [String: ToolResult],
            toolResultsVersion: Int,
            isRerunAllowed: Bool,
            rerunningToolCallIDs: Set<String>,
            onRerunToolCall: @escaping (ToolCall) -> Void
        ) {
            self.conversationID = conversationID
            self.messages = messages
            self.messagesVersion = messagesVersion
            self.streamingMessage = streamingMessage
            self.maxBubbleWidth = maxBubbleWidth
            self.assistantDisplayName = assistantDisplayName
            self.assistantIcon = assistantIcon
            self.toolResultsByCallID = toolResultsByCallID
            self.toolResultsVersion = toolResultsVersion
            self.isRerunAllowed = isRerunAllowed
            self.rerunningToolCallIDs = rerunningToolCallIDs
            self.onRerunToolCall = onRerunToolCall
        }

        deinit {
            if let clipBoundsObserver {
                NotificationCenter.default.removeObserver(clipBoundsObserver)
            }
        }

        func attach(tableView: NSTableView, scrollView: NSScrollView) {
            self.tableView = tableView
            self.scrollView = scrollView

            // Track scrolling + resize via the clip view.
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.handleClipViewBoundsChanged()
            }

            // Initial column sizing.
            resizeSingleColumnIfNeeded()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            messages.count + (streamingMessage == nil ? 0 : 1)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? ChatRowCellView)
                ?? ChatRowCellView()
            cell.identifier = Self.cellID

            if let streamingMessage, row == messages.count {
                cell.apply(
                    kind: .streaming(streamingMessage),
                    maxBubbleWidth: maxBubbleWidth,
                    assistantDisplayName: assistantDisplayName,
                    assistantIcon: assistantIcon,
                    toolResultsByCallID: toolResultsByCallID,
                    isRerunAllowed: isRerunAllowed,
                    rerunningToolCallIDs: rerunningToolCallIDs,
                    onRerunToolCall: onRerunToolCall,
                    onStreamingContentUpdate: { [weak self] in
                        self?.handleStreamingContentUpdate()
                    }
                )
            } else {
                let message = messages[row]
                cell.apply(
                    kind: .message(message),
                    maxBubbleWidth: maxBubbleWidth,
                    assistantDisplayName: assistantDisplayName,
                    assistantIcon: assistantIcon,
                    toolResultsByCallID: toolResultsByCallID,
                    isRerunAllowed: isRerunAllowed,
                    rerunningToolCallIDs: rerunningToolCallIDs,
                    onRerunToolCall: onRerunToolCall,
                    onStreamingContentUpdate: nil
                )
            }

            return cell
        }

        func applyUpdate(
            conversationID: UUID,
            messages: [MessageEntity],
            messagesVersion: Int,
            streamingMessage: StreamingMessageState?,
            maxBubbleWidth: CGFloat,
            assistantDisplayName: String,
            assistantIcon: String?,
            toolResultsByCallID: [String: ToolResult],
            toolResultsVersion: Int,
            isRerunAllowed: Bool,
            rerunningToolCallIDs: Set<String>,
            onRerunToolCall: @escaping (ToolCall) -> Void
        ) {
            guard let tableView else { return }

            let oldHasStreaming = self.streamingMessage != nil

            let isConversationChanged = conversationID != self.conversationID
            let didMessagesChange = messagesVersion != self.messagesVersion
            let didStreamingRowChange = (streamingMessage != nil) != oldHasStreaming
            let didMaxBubbleWidthChange = abs(maxBubbleWidth - self.maxBubbleWidth) > 0.5
            let didToolResultsChange = toolResultsVersion != self.toolResultsVersion
            let didRerunAllowedChange = isRerunAllowed != self.isRerunAllowed
            let didRerunningToolCallsChange = rerunningToolCallIDs != self.rerunningToolCallIDs
            let didAssistantChange = assistantDisplayName != self.assistantDisplayName || assistantIcon != self.assistantIcon

            let oldMessageIDs: [UUID]
            if didMessagesChange || didStreamingRowChange || isConversationChanged {
                // Only compute IDs when we actually need to mutate the table view.
                oldMessageIDs = self.messages.map(\.id)
            } else {
                oldMessageIDs = []
            }

            self.conversationID = conversationID
            self.messages = messages
            self.messagesVersion = messagesVersion
            self.streamingMessage = streamingMessage
            self.maxBubbleWidth = maxBubbleWidth
            self.assistantDisplayName = assistantDisplayName
            self.assistantIcon = assistantIcon
            self.toolResultsByCallID = toolResultsByCallID
            self.toolResultsVersion = toolResultsVersion
            self.isRerunAllowed = isRerunAllowed
            self.rerunningToolCallIDs = rerunningToolCallIDs
            self.onRerunToolCall = onRerunToolCall

            if isConversationChanged {
                tableView.reloadData()
                resizeSingleColumnIfNeeded()
                scrollToBottom(force: true)
                return
            }

            if didMessagesChange || didStreamingRowChange {
                applyRowUpdates(
                    oldMessageIDs: oldMessageIDs,
                    oldHasStreaming: oldHasStreaming,
                    newMessageIDs: messages.map(\.id),
                    newHasStreaming: streamingMessage != nil
                )
                resizeSingleColumnIfNeeded()
                if isPinnedToBottom {
                    scrollToBottom(force: false)
                }
            }

            let needsVisibleCellUpdate = didMaxBubbleWidthChange
                || didToolResultsChange
                || didRerunAllowedChange
                || didRerunningToolCallsChange
                || didAssistantChange

            if needsVisibleCellUpdate {
                updateVisibleCells(updateToolResults: didToolResultsChange)
                noteVisibleRowHeights()
            }
        }

        private func applyRowUpdates(
            oldMessageIDs: [UUID],
            oldHasStreaming: Bool,
            newMessageIDs: [UUID],
            newHasStreaming: Bool
        ) {
            guard let tableView else { return }

            // If only the streaming row appears/disappears, keep it super cheap.
            if newMessageIDs == oldMessageIDs, oldHasStreaming != newHasStreaming {
                tableView.beginUpdates()
                if oldHasStreaming, !newHasStreaming {
                    tableView.removeRows(at: IndexSet(integer: newMessageIDs.count), withAnimation: [])
                } else if !oldHasStreaming, newHasStreaming {
                    tableView.insertRows(at: IndexSet(integer: newMessageIDs.count), withAnimation: [])
                }
                tableView.endUpdates()
                return
            }

            // Fast path: append-only updates (most chats).
            // If we can't prove it's append-only, fall back to reload.
            if newMessageIDs.starts(with: oldMessageIDs) {
                tableView.beginUpdates()

                if newMessageIDs.count > oldMessageIDs.count {
                    let inserted = IndexSet(integersIn: oldMessageIDs.count..<newMessageIDs.count)
                    tableView.insertRows(at: inserted, withAnimation: [])
                }

                if oldHasStreaming && !newHasStreaming {
                    tableView.removeRows(at: IndexSet(integer: newMessageIDs.count), withAnimation: [])
                } else if !oldHasStreaming && newHasStreaming {
                    tableView.insertRows(at: IndexSet(integer: newMessageIDs.count), withAnimation: [])
                }

                tableView.endUpdates()
                return
            }

            tableView.reloadData()
        }

        private func handleClipViewBoundsChanged() {
            updatePinnedToBottom()
            resizeSingleColumnIfNeeded()
        }

        private func updatePinnedToBottom() {
            guard let scrollView else { return }
            let distance = distanceToBottom(in: scrollView)
            isPinnedToBottom = distance < 40
        }

        private func distanceToBottom(in scrollView: NSScrollView) -> CGFloat {
            guard let documentView = scrollView.documentView else { return .greatestFiniteMagnitude }
            let visibleRect = scrollView.documentVisibleRect
            if documentView.isFlipped {
                return documentView.bounds.maxY - visibleRect.maxY
            }
            return visibleRect.minY - documentView.bounds.minY
        }

        private func resizeSingleColumnIfNeeded() {
            guard let tableView, let scrollView else { return }
            guard let column = tableView.tableColumns.first else { return }

            let width = scrollView.contentView.bounds.width
            guard abs(width - lastColumnWidth) > 0.5 else { return }
            lastColumnWidth = width

            column.width = width
        }

        private func updateVisibleCells(updateToolResults: Bool) {
            guard let tableView else { return }
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.location != NSNotFound, visibleRange.length > 0 else { return }
            let visibleRows = IndexSet(integersIn: visibleRange.location..<(visibleRange.location + visibleRange.length))
            for row in visibleRows {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatRowCellView else { continue }
                cell.updateGlobals(
                    maxBubbleWidth: maxBubbleWidth,
                    assistantDisplayName: assistantDisplayName,
                    assistantIcon: assistantIcon,
                    toolResultsByCallID: updateToolResults ? toolResultsByCallID : nil,
                    isRerunAllowed: isRerunAllowed,
                    rerunningToolCallIDs: rerunningToolCallIDs,
                    onRerunToolCall: onRerunToolCall
                )
            }
        }

        private func noteVisibleRowHeights() {
            guard let tableView else { return }
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.location != NSNotFound, visibleRange.length > 0 else { return }
            let visibleRows = IndexSet(integersIn: visibleRange.location..<(visibleRange.location + visibleRange.length))
            tableView.noteHeightOfRows(withIndexesChanged: visibleRows)
        }

        private func handleStreamingContentUpdate() {
            scheduleStreamingRowHeightUpdate()
            throttledAutoScrollToBottom()
        }

        private func scheduleStreamingRowHeightUpdate() {
            pendingStreamingHeightUpdate?.cancel()

            let now = ProcessInfo.processInfo.systemUptime
            let minInterval: TimeInterval = 0.08
            guard now - lastStreamingHeightUpdateUptime >= minInterval else { return }
            lastStreamingHeightUpdateUptime = now

            let item = DispatchWorkItem { [weak self] in
                guard let self, let tableView else { return }
                let streamingRow = self.messages.count
                guard streamingRow < tableView.numberOfRows else { return }
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: streamingRow))
            }
            pendingStreamingHeightUpdate = item
            DispatchQueue.main.async(execute: item)
        }

        private func throttledAutoScrollToBottom() {
            guard isPinnedToBottom else { return }

            let now = ProcessInfo.processInfo.systemUptime
            let minInterval: TimeInterval = 0.25
            guard now - lastAutoScrollUptime >= minInterval else { return }
            lastAutoScrollUptime = now

            scrollToBottom(force: false)
        }

        fileprivate func scrollToBottom(force: Bool) {
            guard let tableView else { return }
            guard force || isPinnedToBottom else { return }
            let row = max(0, tableView.numberOfRows - 1)
            guard row >= 0 else { return }
            tableView.scrollRowToVisible(row)
        }
    }
}

private final class ChatRowContext: ObservableObject {
    enum Kind {
        case empty
        case message(MessageEntity)
        case streaming(StreamingMessageState)
    }

    @Published var kind: Kind
    @Published var maxBubbleWidth: CGFloat
    @Published var assistantDisplayName: String
    @Published var assistantIcon: String?
    @Published var toolResultsByCallID: [String: ToolResult]
    @Published var isRerunAllowed: Bool
    @Published var rerunningToolCallIDs: Set<String>

    var onRerunToolCall: (ToolCall) -> Void
    var onStreamingContentUpdate: (() -> Void)?

    init(
        kind: Kind,
        maxBubbleWidth: CGFloat,
        assistantDisplayName: String,
        assistantIcon: String?,
        toolResultsByCallID: [String: ToolResult],
        isRerunAllowed: Bool,
        rerunningToolCallIDs: Set<String>,
        onRerunToolCall: @escaping (ToolCall) -> Void
    ) {
        self.kind = kind
        self.maxBubbleWidth = maxBubbleWidth
        self.assistantDisplayName = assistantDisplayName
        self.assistantIcon = assistantIcon
        self.toolResultsByCallID = toolResultsByCallID
        self.isRerunAllowed = isRerunAllowed
        self.rerunningToolCallIDs = rerunningToolCallIDs
        self.onRerunToolCall = onRerunToolCall
    }
}

private struct ChatRowHostingRootView: View {
    @ObservedObject var context: ChatRowContext

    var body: some View {
        switch context.kind {
        case .empty:
            Color.clear.frame(height: 1)
        case .message(let message):
            MessageRow(
                messageEntity: message,
                maxBubbleWidth: context.maxBubbleWidth,
                assistantDisplayName: context.assistantDisplayName,
                assistantIcon: context.assistantIcon,
                toolResultsByCallID: context.toolResultsByCallID,
                isRerunAllowed: context.isRerunAllowed,
                isToolCallRerunning: { toolCallID in
                    context.rerunningToolCallIDs.contains(toolCallID)
                },
                onRerunToolCall: context.onRerunToolCall
            )
            .id(message.id)
        case .streaming(let state):
            StreamingMessageView(
                state: state,
                maxBubbleWidth: context.maxBubbleWidth,
                assistantDisplayName: context.assistantDisplayName,
                assistantIcon: context.assistantIcon,
                onContentUpdate: {
                    context.onStreamingContentUpdate?()
                }
            )
            .id("streaming")
        }
    }
}

private final class ChatRowCellView: NSTableCellView {
    private let context: ChatRowContext
    private var hostingView: NSHostingView<ChatRowHostingRootView>?

    override init(frame frameRect: NSRect) {
        context = ChatRowContext(
            kind: .empty,
            maxBubbleWidth: 720,
            assistantDisplayName: "Assistant",
            assistantIcon: nil,
            toolResultsByCallID: [:],
            isRerunAllowed: false,
            rerunningToolCallIDs: [],
            onRerunToolCall: { _ in }
        )

        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func apply(
        kind: ChatRowContext.Kind,
        maxBubbleWidth: CGFloat,
        assistantDisplayName: String,
        assistantIcon: String?,
        toolResultsByCallID: [String: ToolResult],
        isRerunAllowed: Bool,
        rerunningToolCallIDs: Set<String>,
        onRerunToolCall: @escaping (ToolCall) -> Void,
        onStreamingContentUpdate: (() -> Void)?
    ) {
        if !isSameKind(kind) {
            context.kind = kind
        }
        updateGlobals(
            maxBubbleWidth: maxBubbleWidth,
            assistantDisplayName: assistantDisplayName,
            assistantIcon: assistantIcon,
            toolResultsByCallID: toolResultsByCallID,
            isRerunAllowed: isRerunAllowed,
            rerunningToolCallIDs: rerunningToolCallIDs,
            onRerunToolCall: onRerunToolCall
        )
        context.onStreamingContentUpdate = onStreamingContentUpdate

        ensureHostingView()
    }

    func updateGlobals(
        maxBubbleWidth: CGFloat,
        assistantDisplayName: String,
        assistantIcon: String?,
        toolResultsByCallID: [String: ToolResult]?,
        isRerunAllowed: Bool,
        rerunningToolCallIDs: Set<String>,
        onRerunToolCall: @escaping (ToolCall) -> Void
    ) {
        if abs(context.maxBubbleWidth - maxBubbleWidth) > 0.5 {
            context.maxBubbleWidth = maxBubbleWidth
        }
        if context.assistantDisplayName != assistantDisplayName {
            context.assistantDisplayName = assistantDisplayName
        }
        if context.assistantIcon != assistantIcon {
            context.assistantIcon = assistantIcon
        }
        if context.isRerunAllowed != isRerunAllowed {
            context.isRerunAllowed = isRerunAllowed
        }
        if context.rerunningToolCallIDs != rerunningToolCallIDs {
            context.rerunningToolCallIDs = rerunningToolCallIDs
        }

        if let toolResultsByCallID {
            context.toolResultsByCallID = toolResultsByCallID
        }
        context.onRerunToolCall = onRerunToolCall
    }

    private func isSameKind(_ kind: ChatRowContext.Kind) -> Bool {
        switch (context.kind, kind) {
        case (.empty, .empty):
            return true
        case (.message(let a), .message(let b)):
            return a.id == b.id
        case (.streaming, .streaming):
            return true
        default:
            return false
        }
    }

    private func ensureHostingView() {
        guard hostingView == nil else { return }

        let hostingView = NSHostingView(rootView: ChatRowHostingRootView(context: context))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        self.hostingView = hostingView
    }
}
