import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// Ground truth for the "clipped bubble + giant gap" family: hosts a REAL
/// `MessageRow` in a REAL `ChatTimelineHostingCell`, sizes the cell to the row
/// height the controller would apply, then reads the PIXELS the cell paints.
///
/// The invariant every fix in this family has to satisfy:
///
///   last painted pixel row ≈ the row height the table applied
///
/// A short paint bottom means content was cut (the bubble clipped mid-line);
/// a paint bottom far above the row height means the row reserved space
/// nothing paints into (the one-viewport gap). One measurement catches both,
/// which is exactly what the pure-number height tests could not.
@MainActor
final class ChatTimelineRowPaintGeometryTests: XCTestCase {

    // Real geometry from the reported window: column 1120pt inside a ~1.8k
    // wide table, user bubbles wrapping at 70% of the column.
    private let cellWidth: CGFloat = 1_800
    private let columnWidth: CGFloat = 1_120

    // MARK: - Cases

    func testLongUserMarkdownRowPaintsEverythingItReserves() throws {
        try assertPaintMatchesRowHeight(
            label: "long-user-markdown",
            item: makeItem(role: "user", text: Self.reportedUserMessage)
        )
    }

    func testLongAssistantMarkdownRowPaintsEverythingItReserves() throws {
        try assertPaintMatchesRowHeight(
            label: "long-assistant-markdown",
            item: makeItem(role: "assistant", text: Self.reportedUserMessage)
        )
    }

    func testAssistantRowWithThinkingPaintsEverythingItReserves() throws {
        let blocks: [RenderedMessageBlock] = [
            .content(
                anchorID: "thinking-0",
                part: .thinking(ThinkingBlock(text: Self.thinkingText, provider: nil))
            ),
            .content(anchorID: "text-0", part: .text(Self.reportedUserMessage)),
        ]
        try assertPaintMatchesRowHeight(
            label: "assistant-thinking",
            item: makeItem(role: "assistant", blocks: blocks, copyText: Self.reportedUserMessage)
        )
    }

    func testShortUserRowPaintsEverythingItReserves() throws {
        try assertPaintMatchesRowHeight(
            label: "short-user",
            item: makeItem(role: "user", text: "review简洁些，ai味道别太重了")
        )
    }

    /// The cell is the clip boundary, so hosted content must sit at its TOP
    /// under every resize — including resizes AppKit performs without running
    /// the cell's constraints again (the table re-tiles rows outside the
    /// cell's own layout pass).
    ///
    /// `NSTableCellView` is not a flipped view, so a subview pinned to the top
    /// is bottom-anchored in raw coordinates: without a constraint pass, a
    /// resized cell leaves the host at its old offset — riding above the cell's
    /// top when it shrinks (header and first lines masked away, which is the
    /// "top of the reply is missing until I scroll" report) and pushed down
    /// when it grows. Nothing in the row-height path guarantees that pass.
    func testHostedContentStaysPinnedToTheCellTopAcrossResizesWithoutLayout() throws {
        let shared = makeShared()
        let cell = ChatTimelineHostingCell()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: cellWidth, height: 4_000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: cellWidth, height: 4_000))
        window.contentView = container
        container.addSubview(cell)
        cell.frame = NSRect(x: 0, y: 0, width: cellWidth, height: 600)
        cell.configure(
            identity: "resize-probe",
            content: AnyView(
                chatTimelineCenteredContent(
                    ChatTimelineMessageContent(
                        item: makeItem(role: "assistant", text: Self.reportedUserMessage),
                        index: 0,
                        shared: shared
                    ),
                    shared: shared,
                    onContentHeight: { _ in }
                )
            )
        )
        settle(window)

        // Resize the way the table does: frame only, no forced layout of the
        // cell's subtree afterwards.
        for height in [340.0, 900.0, 200.0, 620.0] as [CGFloat] {
            cell.setFrameSize(NSSize(width: cellWidth, height: height))
            let hostTop = cell.isFlipped
                ? cell.host.frame.minY
                : cell.frame.height - cell.host.frame.maxY
            XCTAssertEqual(
                hostTop,
                0,
                accuracy: 1,
                "after resizing the cell to \(height)pt the hosted content starts \(hostTop)pt from its top "
                    + "— that offset is masked away (content cut off at the row's edge)"
            )
        }
    }

    // MARK: - The probe

    /// Realizes the row the way the table does, then compares three numbers
    /// that must agree: the height the cell reports (what becomes the row
    /// height), the height of the SwiftUI host's frame (the paint slot), and
    /// the bottom of the painted pixels.
    private func assertPaintMatchesRowHeight(
        label: String,
        item: MessageRenderItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let probe = try realize(item: item)

        // Diagnostic first — a failure here is only useful with the numbers.
        print("""
        [row-paint] \(label)
          reported(GeometryReader) = \(probe.reportedHeight)
          measuredContentHeight()  = \(probe.measuredHeight)
          host.fittingSize.height  = \(probe.fittingHeight)
          host.intrinsic.height    = \(probe.intrinsicHeight)
          host.frame.height        = \(probe.hostFrameHeight)  <- paint slot
          row height applied       = \(probe.rowHeight)
          painted rows             = \(probe.paintedTop)...\(probe.paintedBottom)
        """)

        XCTAssertGreaterThan(probe.measuredHeight, 0, "\(label): nothing measured", file: file, line: line)

        // 1. The paint slot must be able to hold everything the row reserves —
        //    a slot shorter than the row is the clipped-bubble mechanism.
        XCTAssertGreaterThanOrEqual(
            probe.hostFrameHeight,
            probe.rowHeight - 1,
            "\(label): SwiftUI host frame (\(probe.hostFrameHeight)) is shorter than the row "
                + "(\(probe.rowHeight)) — content below the host's frame is never painted (clipped bubble)",
            file: file,
            line: line
        )

        // 2. Painting must reach the bottom of the row: anything else is
        //    reserved-but-empty space (the giant gap).
        XCTAssertLessThanOrEqual(
            probe.rowHeight - probe.paintedBottom,
            12,
            "\(label): row is \(probe.rowHeight)pt but paint stops at \(probe.paintedBottom)pt "
                + "— \(probe.rowHeight - probe.paintedBottom)pt of reserved blank (gap)",
            file: file,
            line: line
        )

        // 3. And nothing may be cut off: the content the row was sized for has
        //    to fit inside it.
        XCTAssertLessThanOrEqual(
            probe.measuredHeight,
            probe.rowHeight + 1,
            "\(label): measured content (\(probe.measuredHeight)) exceeds the applied row height "
                + "(\(probe.rowHeight)) — the cell mask cuts the remainder",
            file: file,
            line: line
        )
    }

    private struct Probe {
        let reportedHeight: CGFloat
        let measuredHeight: CGFloat
        let fittingHeight: CGFloat
        let intrinsicHeight: CGFloat
        let hostFrameHeight: CGFloat
        let rowHeight: CGFloat
        let paintedTop: CGFloat
        let paintedBottom: CGFloat
    }

    private func realize(item: MessageRenderItem) throws -> Probe {
        let shared = makeShared()
        let cell = ChatTimelineHostingCell()
        var reported: CGFloat = 0
        cell.onMeasuredHeight = { _, _ in }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: cellWidth, height: 4_000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: cellWidth, height: 4_000))
        window.contentView = container
        container.addSubview(cell)

        // Start at a deliberately WRONG height (the estimator's job), exactly
        // like a freshly inserted row, so the probe exercises the correction
        // path instead of a lucky first guess.
        cell.frame = NSRect(x: 0, y: 0, width: cellWidth, height: 96)
        cell.configure(
            identity: "msg-\(item.id.uuidString)",
            content: AnyView(
                chatTimelineCenteredContent(
                    ChatTimelineMessageContent(item: item, index: 0, shared: shared),
                    shared: shared,
                    onContentHeight: { reported = $0 }
                )
            )
        )
        settle(window)

        // Apply the row height the controller would apply, then let layout land.
        let measured = cell.measuredContentHeight()
        cell.frame = NSRect(x: 0, y: 0, width: cellWidth, height: measured)
        settle(window)

        let painted = paintedRowRange(of: cell)
        return Probe(
            reportedHeight: reported,
            measuredHeight: cell.measuredContentHeight(),
            fittingHeight: cell.host.fittingSize.height,
            intrinsicHeight: cell.host.intrinsicContentSize.height,
            hostFrameHeight: cell.host.frame.height,
            rowHeight: cell.frame.height,
            paintedTop: painted.top,
            paintedBottom: painted.bottom
        )
    }

    /// Drains the main run loop so async markdown parsing / SwiftUI updates
    /// land, then forces a full layout+display pass.
    private func settle(_ window: NSWindow) {
        for _ in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        window.contentView?.displayIfNeeded()
    }

    /// Top and bottom of the painted (non-transparent) region of `view`, in
    /// the view's own flipped coordinates. Uses the same clipping the user
    /// sees: `cacheDisplay` honours `clipsToBounds` / layer masks.
    private func paintedRowRange(of view: NSView) -> (top: CGFloat, bottom: CGFloat) {
        guard view.bounds.height >= 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return (0, 0)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData else { return (0, 0) }

        let bytesPerRow = rep.bytesPerRow
        let samples = rep.samplesPerPixel
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let scaleY = view.bounds.height / CGFloat(max(1, height))

        var top = -1
        var bottom = -1
        for y in 0..<height {
            var rowHasInk = false
            let rowStart = data + y * bytesPerRow
            var x = 0
            while x < width {
                let pixel = rowStart + x * samples
                // Alpha is the last sample when present; otherwise any
                // non-black component counts as ink.
                let alpha = samples >= 4 ? pixel[3] : 255
                if alpha > 8, samples >= 3, pixel[0] | pixel[1] | pixel[2] != 0 {
                    rowHasInk = true
                    break
                }
                x += 1
            }
            if rowHasInk {
                if top < 0 { top = y }
                bottom = y
            }
        }
        guard top >= 0 else { return (0, 0) }
        // `+1` converts the last inked ROW index into a bottom EDGE.
        return (CGFloat(top) * scaleY, CGFloat(bottom + 1) * scaleY)
    }

    // MARK: - Fixtures

    private final class FlippedContainer: NSView {
        override var isFlipped: Bool { true }
    }

    private func makeItem(
        role: String,
        text: String? = nil,
        blocks: [RenderedMessageBlock]? = nil,
        copyText: String? = nil
    ) -> MessageRenderItem {
        let renderedBlocks = blocks
            ?? [.content(anchorID: "text-0", part: .text(text ?? ""))]
        return MessageRenderItem(
            id: UUID(),
            role: role,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: renderedBlocks,
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: role == "assistant" ? "gpt-5.6-sol" : nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: copyText ?? text ?? "",
            preferredRenderMode: .nativeText,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: role == "user",
            canDeleteResponse: role == "assistant",
            perMessageMCPServerNames: []
        )
    }

    private func makeShared() -> ChatTimelineSharedInputs {
        ChatTimelineSharedInputs(
            maxBubbleWidth: ChatConversationLayoutMetrics.assistantBubbleMaxWidth(for: columnWidth),
            columnWidth: columnWidth,
            layoutCenterOffset: 0,
            assistantDisplayName: "Jin",
            providerType: .openai,
            providerIconID: nil,
            eagerCodeHighlightStartIndex: 0,
            payloadResolver: .noop,
            toolResultsByCallID: [:],
            messageEntitiesByID: [:],
            interaction: makeInteraction(),
            onOpenArtifact: { _ in },
            effectiveRenderMode: { _, _ in .nativeText },
            onExpandCollapsedContent: { _ in },
            colorScheme: .dark
        )
    }

    private func makeInteraction() -> ChatMessageInteractionContext {
        ChatMessageInteractionContext(
            textToSpeechEnabled: false,
            textToSpeechConfigured: false,
            textToSpeechPlaybackState: .idle,
            editingUserMessageID: nil,
            editingUserMessageText: .constant(""),
            editingUserMessageFocused: .constant(false),
            textToSpeechIsGenerating: { _ in false },
            textToSpeechIsPlaying: { _ in false },
            textToSpeechIsPaused: { _ in false },
            onToggleSpeakAssistantMessage: { _, _ in },
            onStopSpeakAssistantMessage: { _ in },
            onRegenerate: { _ in },
            onEditUserMessage: { _ in },
            onSubmitUserEdit: { _ in },
            onCancelUserEdit: {},
            onDeleteMessage: { _ in },
            onDeleteResponse: { _ in },
            onQuoteSelection: { _, _, _ in },
            onCreateHighlight: { _ in },
            onRemoveHighlights: { _ in },
            editSlashCommand: .inactive
        )
    }

    private static let thinkingText = String(
        repeating: "**Evaluating the paper**\n\nWeighing the claims against the measurements. ",
        count: 12
    )

    /// The exact user message the reported screenshot clipped (conversation
    /// 491, message 4433) — markdown headings, bold runs, numbered weaknesses
    /// and a CJK tail, which is what makes the ideal-size and wrapped-size
    /// answers diverge.
    private static let reportedUserMessage = """
    ## Review

    **Recommendation:** Borderline / Weak Accept
    **Confidence:** 4/5

    ### Summary

    FlexDiT is a serving system for DiT-based image and video generation. Its main idea is to avoid assigning one fixed GPU group to an entire request. It chooses a target DoP from offline profiles, allows DiT requests to start with fewer GPUs and scale up at denoising-step boundaries, and allocates DiT and VAE separately. The system is implemented on VideoSys and SGLang Diffusion and evaluated with OpenSora and Z-Image.

    ### Strengths

    S1.The problem is important, and the motivation is convincing. In particular, the measurements showing resolution-dependent DiT scaling and different DiT/VAE behavior are useful.

    S2.The design is practical. Restricting reallocation to step boundaries avoids full preemption while still allowing released GPUs to be reused.

    S3.The evaluation covers both T2V and T2I, two runtimes, and several relevant ablations. The ablations on phase decoupling and promotion policy are especially helpful.

    ### Weaknesses

    W1.**The paper talks a lot about resource efficiency, but does not measure it directly.** Most results are latency and SLO attainment. I would like to see GPU seconds per request, utilization, and goodput. Otherwise, it is hard to tell how much of the gain comes from using resources more efficiently versus changing request ordering.

    W2.**The high-load results need more explanation.** The paper says the queue grows continuously after saturation. In that case, P90/P99 depend on the trace length and number of requests. These details, along with variance across runs and per-resolution latency, should be reported.

    W3.**Some conclusions are specific to the evaluated runtimes.** The VAE result partly comes from VideoSys and SGLang replicating VAE work across ranks. Likewise, the T2I batching conclusion is mostly inferred rather than directly measured. The observations are still valuable, but the claims should be scoped more carefully.

    W4.**The scale-out claim is somewhat limited.** In the two-node experiment, each request remains within one node, and the 64-GPU experiment is simulated. This demonstrates cluster-level scheduling, but not cross-node elastic execution.

    ### Overall

    The problem is well motivated and the experiments suggest that the approach is useful. My main concern is that the evaluation does not directly support the paper's resource efficiency claim, and some of the broader conclusions are based on runtime-specific behavior. These issues seem fixable, so I am currently **borderline, leaning weak accept**.你觉得这个review怎么样，帮我改改，看能不能改成weak reject吧，SoCC2026
    """
}
