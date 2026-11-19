import AppKit
import SwiftUI
import XCTest
@testable import Jin

private struct DeterministicRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@MainActor
final class ChatTimelineRowOverlapRegressionTests: XCTestCase {

    private func makeWindowAndController(width: CGFloat = 1100, height: CGFloat = 800) -> (NSWindow, ChatTimelineTableController, NSScrollView, NSTableView) {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: width, height: height),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = ChatTimelineTableController()
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = controller.view
        window.makeKeyAndOrderFront(nil)
        let scrollView = controller.view as! NSScrollView
        let tableView = scrollView.documentView as! NSTableView
        return (window, controller, scrollView, tableView)
    }

    private func makeItems(count: Int = 40) -> [MessageRenderItem] {
        (0..<count).map { i in
            if i % 2 == 0 {
                let text: String
                switch i % 6 {
                case 0:
                    text = TimelineRowFixtures.codeAndTableReply + "\n\n**要分别叙述，不能全部合成“serverless让训练更快”。**"
                case 2:
                    text = TimelineRowFixtures.assistantReply
                default:
                    text = TimelineRowFixtures.shortAssistantReply
                }
                return TimelineRowFixtures.thinkingItem(text: text, thinking: TimelineRowFixtures.thinkingText)
            } else {
                return TimelineRowFixtures.item(
                    role: "user",
                    text: (i % 4 == 1)
                        ? "这些 serverless 系统的函数一般是自己建还是用 azure, aws 这些?"
                        : TimelineRowFixtures.cjkUserFollowUp
                )
            }
        }
    }

    private func assertCleanRowGeometry(
        _ tableView: NSTableView,
        label: String,
        requireExactCellMatch: Bool = false
    ) {
        var rowFrames: [(row: Int, rowView: NSTableRowView)] = []
        for subview in tableView.subviews {
            guard let rowView = subview as? NSTableRowView, !rowView.isHidden else { continue }
            let row = tableView.row(for: rowView)
            XCTAssertGreaterThanOrEqual(row, 0, "[\(label)] orphan visible NSTableRowView \(rowView.frame)")
            guard row >= 0 else { continue }
            rowFrames.append((row, rowView))

            XCTAssertEqual(rowView.subviews.count, 1, "[\(label)] row \(row) expected 1 subview, got \(rowView.subviews.count)")
            let expected = tableView.rect(ofRow: row)
            XCTAssertEqual(rowView.frame.minY, expected.minY, accuracy: 1.0, "[\(label)] row \(row) minY desync: \(rowView.frame) vs \(expected)")
            XCTAssertEqual(rowView.frame.height, expected.height, accuracy: 1.0, "[\(label)] row \(row) height desync: \(rowView.frame) vs \(expected)")

            if let cell = rowView.view(atColumn: 0) as? ChatTimelineHostingCell {
                XCTAssertTrue(cell.superview === rowView, "[\(label)] row \(row) cell.superview !== rowView")
                XCTAssertTrue(cell.clipsToBounds, "[\(label)] row \(row) cell.clipsToBounds must be true")
                XCTAssertEqual(cell.layer?.masksToBounds, true, "[\(label)] row \(row) cell.layer?.masksToBounds must be true")
                let expectedCellHeight = rowView.bounds.height - tableView.intercellSpacing.height
                XCTAssertEqual(cell.frame.height, expectedCellHeight, accuracy: 1.0, "[\(label)] row \(row) cell height desync")
                if requireExactCellMatch {
                    let measured = cell.measuredContentHeight()
                    if measured > 1 {
                        XCTAssertEqual(cell.frame.height, measured, accuracy: 2.0, "[\(label)] row \(row) cell.h=\(cell.frame.height) != measured=\(measured)")
                    }
                }
            }
        }

        rowFrames.sort { $0.rowView.frame.minY < $1.rowView.frame.minY }
        for idx in 0..<max(0, rowFrames.count - 1) {
            let current = rowFrames[idx]
            let next = rowFrames[idx + 1]
            XCTAssertLessThanOrEqual(
                current.rowView.frame.maxY,
                next.rowView.frame.minY + 0.5,
                "[\(label)] row \(current.row) \(current.rowView.frame) overlaps row \(next.row) \(next.rowView.frame)"
            )
        }
    }

    /// Guards against implicit AppKit row animations during `reloadInPlace`
    /// (window slide / streaming->finished swap) overlapping adjacent rows.
    func testSlidingReloadInPlaceNeverAnimatesRowsIntoOverlap() {
        NativeMarkdownCache.purgeForMemoryPressure()
        let (window, controller, scrollView, tableView) = makeWindowAndController(width: 950, height: 800)
        defer { window.orderOut(nil) }

        var allItems = makeItems(count: 45)
        let convID = UUID()
        let colW = ChatConversationLayoutMetrics.messageColumnWidth(for: 950)

        func applySlice(_ slice: ArraySlice<MessageRenderItem>, hidden: Int, seed: Int) {
            var rows: [ChatTimelineRow] = [.loadEarlier(hiddenCount: hidden, pageSize: 40)]
            for (idx, item) in slice.enumerated() {
                rows.append(.message(item, index: idx))
            }
            controller.apply(
                ChatTimelineTableController.Model(
                    conversationID: convID,
                    rows: rows,
                    shared: TimelineRowFixtures.shared(columnWidth: colW),
                    contentEpoch: TimelineRowFixtures.epoch(entityCount: slice.count + seed),
                    streamingMessage: nil,
                    topInset: 24,
                    bottomInset: 100,
                    bottomTolerance: 40,
                    nextRenderLimit: 40,
                    canLoadEarlier: hidden > 0,
                    setPinned: { _ in },
                    setRenderLimit: { _ in },
                    onLoadEarlier: {}
                )
            )
        }

        applySlice(allItems[4..<44], hidden: 4, seed: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: max(0, tableView.frame.height - 1200)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))

        // Slide by 1 (equal row count -> reloadInPlace).
        allItems.append(TimelineRowFixtures.item(role: "user", text: "Follow up"))
        applySlice(allItems[5..<45], hidden: 5, seed: 1)
        assertCleanRowGeometry(tableView, label: "reloadInPlace-immediate")

        RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        assertCleanRowGeometry(tableView, label: "reloadInPlace-mid-tick")

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        assertCleanRowGeometry(tableView, label: "reloadInPlace-settled", requireExactCellMatch: true)
    }

    /// Guards against `reloadVisibleContent` / `reloadSurvivingRowsIfNeeded`
    /// mutating table heights from inside `enumerateAvailableRowViews`
    /// (which previously threw `-[NSTableRowView integerValue]` and orphaned cells),
    /// and against `widthChanged && rowIDsChanged` skipping survivor re-wrap.
    func testWidthAndEpochChurnWithRowMutationsPreservesCellOwnership() {
        NativeMarkdownCache.purgeForMemoryPressure()
        let (window, controller, _, tableView) = makeWindowAndController(width: 1100, height: 800)
        defer { window.orderOut(nil) }

        var items = makeItems(count: 42)
        let convID = UUID()
        var width: CGFloat = 1100
        var editingID: UUID?
        var epochCount = 0

        func applyWindow(slice: ArraySlice<MessageRenderItem>, hidden: Int) {
            var rows: [ChatTimelineRow] = [.loadEarlier(hiddenCount: hidden, pageSize: 40)]
            for (idx, item) in slice.enumerated() {
                rows.append(.message(item, index: idx))
            }
            let epoch = ChatTimelineContentEpoch(
                renderRevision: epochCount,
                hiddenCount: hidden,
                eagerCodeHighlightStartIndex: max(0, slice.count - 6),
                layoutCenterOffsetBucket: 0,
                assistantDisplayName: "Jin",
                providerType: .openai,
                providerIconID: nil,
                toolResultsByCallID: [:],
                entityCount: items.count,
                editingUserMessageID: editingID,
                editSlashCommandKey: .inactive,
                textToSpeechEnabled: false,
                textToSpeechConfigured: false,
                textToSpeechPlaybackState: .idle,
                expandedCollapsedMessageIDs: [],
                colorScheme: .light,
                appFontFamily: "",
                codeFontFamily: "",
                streamingObjectID: nil,
                streamingModelLabel: nil,
                streamingModelID: nil,
                streamingSuppressesIdlePlaceholder: false
            )
            let colW = ChatConversationLayoutMetrics.messageColumnWidth(for: width)
            controller.apply(
                ChatTimelineTableController.Model(
                    conversationID: convID,
                    rows: rows,
                    shared: TimelineRowFixtures.shared(columnWidth: colW),
                    contentEpoch: epoch,
                    streamingMessage: nil,
                    topInset: 24,
                    bottomInset: 100,
                    bottomTolerance: 40,
                    nextRenderLimit: 40,
                    canLoadEarlier: hidden > 0,
                    setPinned: { _ in },
                    setRenderLimit: { _ in },
                    onLoadEarlier: {}
                )
            )
        }

        applyWindow(slice: items[2..<42], hidden: 2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        for (step, nextWidth) in ([750, 1400, 950, 1200] as [CGFloat]).enumerated() {
            width = nextWidth
            window.setContentSize(NSSize(width: width, height: 800))
            controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 800)
            editingID = (step % 2 == 0) ? items.last(where: { $0.isUser })?.id : nil
            epochCount += 1
            items.append(TimelineRowFixtures.item(role: step % 2 == 0 ? "user" : "assistant", text: "Message \(step)"))
            applyWindow(slice: items.suffix(40), hidden: items.count - 40)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            assertCleanRowGeometry(tableView, label: "width+mutation-\(step)")
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        assertCleanRowGeometry(tableView, label: "width+mutation-settled", requireExactCellMatch: true)
    }

    /// Guards against `batchDiff` + animated `scrollTo` realizing unmeasured rows
    /// above an already-tiled row and leaving the resident `NSTableRowView`
    /// frames desynced or overlapping `rect(ofRow:)`.
    func testBatchDiffAndAnimatedScrollNeverLeaveResidentRowsDesynced() {
        NativeMarkdownCache.purgeForMemoryPressure()
        let (window, controller, scrollView, tableView) = makeWindowAndController(width: 1100, height: 800)
        defer { window.orderOut(nil) }

        let convs = (0..<3).map { _ in (UUID(), makeItems(count: 40)) }
        var convIdx = 0
        var renderLimit = 24
        var epochSeed = 0
        var streaming: StreamingMessageState?
        var editingID: UUID?
        var width: CGFloat = 1100

        func applyCurrent() {
            let (id, all) = convs[convIdx]
            let tw = ChatMessageStagePresentationSupport.TimelineWindow(
                messages: all,
                renderLimit: renderLimit,
                pageSize: 40,
                eagerCodeHighlightTailCount: 6,
                nonLazyMessageStackThreshold: 4
            )
            let colW = ChatConversationLayoutMetrics.messageColumnWidth(for: width)
            var rows: [ChatTimelineRow] = []
            if tw.canLoadEarlier {
                rows.append(.loadEarlier(hiddenCount: tw.hiddenCount, pageSize: 40))
            }
            for (idx, item) in tw.visibleMessages.enumerated() {
                rows.append(.message(item, index: idx))
            }
            if let s = streaming {
                rows.append(.streaming(s))
            }
            let epoch = ChatTimelineContentEpoch(
                renderRevision: 0,
                hiddenCount: tw.hiddenCount,
                eagerCodeHighlightStartIndex: tw.eagerCodeHighlightStartIndex,
                layoutCenterOffsetBucket: 0,
                assistantDisplayName: "Jin",
                providerType: .openai,
                providerIconID: nil,
                toolResultsByCallID: [:],
                entityCount: all.count + epochSeed,
                editingUserMessageID: editingID,
                editSlashCommandKey: .inactive,
                textToSpeechEnabled: false,
                textToSpeechConfigured: false,
                textToSpeechPlaybackState: .idle,
                expandedCollapsedMessageIDs: [],
                colorScheme: .light,
                appFontFamily: "",
                codeFontFamily: "",
                streamingObjectID: streaming.map(ObjectIdentifier.init),
                streamingModelLabel: nil,
                streamingModelID: nil,
                streamingSuppressesIdlePlaceholder: false
            )
            controller.apply(
                ChatTimelineTableController.Model(
                    conversationID: id,
                    rows: rows,
                    shared: TimelineRowFixtures.shared(columnWidth: colW),
                    contentEpoch: epoch,
                    streamingMessage: streaming,
                    topInset: 24,
                    bottomInset: 100,
                    bottomTolerance: 40,
                    nextRenderLimit: tw.nextRenderLimit,
                    canLoadEarlier: tw.canLoadEarlier,
                    setPinned: { _ in },
                    setRenderLimit: { renderLimit = $0 },
                    onLoadEarlier: {}
                )
            )
        }

        applyCurrent()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        // Seed-30 & Seed-2 critical pattern: resize, narrow/widen render window, scroll, animated jump.
        for seed in [UInt64(2), UInt64(30)] {
            var rng = DeterministicRNG(state: seed)
            for step in 0..<70 {
                let op = Int.random(in: 0..<11, using: &rng)
                switch op {
                case 0, 1, 2:
                    let maxY = max(0, tableView.frame.height - 800)
                    let y = CGFloat.random(in: 0...max(1, maxY), using: &rng)
                    scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                case 3:
                    convIdx = Int.random(in: 0..<convs.count, using: &rng)
                    renderLimit = [12, 24, 40].randomElement(using: &rng)!
                    streaming = nil
                    editingID = nil
                    applyCurrent()
                case 4:
                    width = [750, 950, 1100, 1400].randomElement(using: &rng)!
                    window.setContentSize(NSSize(width: width, height: 800))
                    controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 800)
                    applyCurrent()
                case 5:
                    renderLimit = [16, 24, 40].randomElement(using: &rng)!
                    applyCurrent()
                case 6:
                    if streaming == nil {
                        let s = StreamingMessageState()
                        s.appendTextDelta("Streaming **hello**")
                        streaming = s
                    } else if Bool.random(using: &rng) {
                        streaming?.appendTextDelta("\n\nMore **text** here")
                    } else {
                        streaming = nil
                    }
                    applyCurrent()
                case 7:
                    epochSeed += 1
                    applyCurrent()
                case 8:
                    editingID = editingID == nil ? convs[convIdx].1.last(where: { $0.isUser })?.id : nil
                    applyCurrent()
                default:
                    if Bool.random(using: &rng) {
                        controller.scrollToBottom(animated: Bool.random(using: &rng), force: true)
                    } else if let mid = convs[convIdx].1.randomElement()?.id {
                        controller.scrollTo(messageID: mid, animated: Bool.random(using: &rng))
                    }
                }
                let wait = Double.random(in: 0.002...0.03, using: &rng)
                RunLoop.current.run(until: Date().addingTimeInterval(wait))
                assertCleanRowGeometry(tableView, label: "seed\(seed)-step\(step)")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            assertCleanRowGeometry(tableView, label: "seed\(seed)-settled", requireExactCellMatch: true)
        }
    }
}
