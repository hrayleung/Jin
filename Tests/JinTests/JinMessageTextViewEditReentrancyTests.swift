import AppKit
import XCTest
@testable import Jin

/// The build-658 production crash, pinned.
///
/// `NSTextStorage` fans an edit out to its layout managers one at a time, and
/// AppKit re-enters the app from inside that fan-out: the live manager tells
/// its text view to fix up the selection, `-[NSTextView
/// setSelectedRanges:affinity:stillSelecting:]` posts an accessibility
/// notification, and — when anything is observing accessibility — AppKit
/// services it synchronously. SwiftUI then re-runs `updateNSView` (a second
/// apply, nested inside the first edit) and `sizeThatFits` (a measurement
/// against managers that have not been told about the edit yet). The
/// measurement threw from
/// `-[NSLayoutManager _fillGlyphHoleForCharacterRange:startGlyphIndex:desiredNumberOfCharacters:]`,
/// which is uncatchable inside AppKit's constraint pass, so the app died.
///
/// Every test here re-enters the view from inside a real storage edit, using a
/// layout manager that calls back exactly where AppKit does.
@MainActor
final class JinMessageTextViewEditReentrancyTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 14)

    private func attributed(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font])
    }

    private func prose(_ marker: String, paragraphs: Int) -> NSAttributedString {
        attributed(
            String(
                repeating: "\(marker) resolution-dependent 段落 with enough text to wrap several times. ",
                count: paragraphs
            )
        )
    }

    /// Stands in for AppKit's accessibility notification: re-enters the app
    /// from the middle of the storage's edit fan-out. Added AFTER the view's
    /// live manager and BEFORE the shadow one, which is the ordering that made
    /// the shadow manager stale at the moment it was asked to lay out.
    private final class ReentrantProbeLayoutManager: NSLayoutManager {
        var onEdited: (() -> Void)?

        override func processEditing(
            for textStorage: NSTextStorage,
            edited editMask: NSTextStorageEditActions,
            range newCharRange: NSRange,
            changeInLength delta: Int,
            invalidatedRange invalidatedCharRange: NSRange
        ) {
            super.processEditing(
                for: textStorage,
                edited: editMask,
                range: newCharRange,
                changeInLength: delta,
                invalidatedRange: invalidatedCharRange
            )
            onEdited?()
        }
    }

    /// A view whose live container sits at `liveWidth`, with a shadow manager
    /// already created (an off-width probe) and a re-entrancy probe installed
    /// between the two.
    private func makeView(
        _ initial: NSAttributedString,
        liveWidth: CGFloat,
        probeWidth: CGFloat
    ) -> (view: JinMessageTextView, probe: ReentrantProbeLayoutManager) {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(initial)
        view.setFrameSize(NSSize(width: liveWidth, height: 10))
        view.layoutSubtreeIfNeeded()

        let probe = ReentrantProbeLayoutManager()
        // Order matters: live (0), probe (1), shadow (2). The probe therefore
        // fires while the shadow still describes the previous text — the
        // production window.
        view.textStorage?.addLayoutManager(probe)
        _ = view.computeHeight(forWidth: probeWidth)
        XCTAssertEqual(view.textStorage?.layoutManagers.count, 3, "shadow manager was not created")
        return (view, probe)
    }

    /// Height of `attributed` at `width` measured the ordinary way, by a view
    /// whose live container is already at that width.
    private func liveHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed)
        view.setFrameSize(NSSize(width: width, height: 10))
        view.layoutSubtreeIfNeeded()
        return view.computeHeight(forWidth: width)
    }

    // MARK: - The detector itself

    /// The whole staleness check rests on this override actually being called.
    /// AppKit deprecated the selector the crash log shows
    /// (`-textStorage:edited:…`) in favour of
    /// `-processEditingForTextStorage:edited:…`; if a future SDK stopped
    /// routing through the latter, `jinIsStaleRelativeToStorage` would silently
    /// answer "fresh" forever and the net would be gone.
    func testLayoutManagerRecordsTheStorageLengthItWasNotifiedOf() {
        let view = JinMessageTextView()
        let manager = view.layoutManager as? JinMarkdownLayoutManager
        XCTAssertNotNil(manager, "the live manager is no longer a JinMarkdownLayoutManager")

        view.setScrubbedAttributedString(attributed("first"))
        XCTAssertEqual(manager?.jinNotifiedStorageLength, 5)
        XCTAssertEqual(manager?.jinIsStaleRelativeToStorage, false)

        view.setScrubbedAttributedString(attributed("a much longer replacement"))
        XCTAssertEqual(manager?.jinNotifiedStorageLength, view.textStorage?.length)
        XCTAssertEqual(manager?.jinIsStaleRelativeToStorage, false)
    }

    // MARK: - Measuring from inside an edit

    /// The crash itself: an off-live-width probe arriving from inside a storage
    /// edit. Before the fix this ran `ensureLayout` on a shadow manager that
    /// still believed the previous (longer) text and raised.
    func testMeasuringFromInsideOurOwnEditDoesNotDriveTheLayoutManagers() {
        let (view, probe) = makeView(prose("original", paragraphs: 24), liveWidth: 420, probeWidth: 300)

        let replacement = prose("replacement", paragraphs: 6)
        var probed: CGFloat?
        var probedDuringMutation: Bool?
        probe.onEdited = { [weak view] in
            guard let view, probed == nil else { return }
            probedDuringMutation = view.isMutatingTextStorage
            // A width the live container is NOT at, so this is the shadow path.
            probed = view.computeHeight(forWidth: 260)
        }

        let fallbacksBefore = JinLayoutCostCounters.midEditMeasurements
        view.setScrubbedAttributedString(replacement)

        XCTAssertEqual(probedDuringMutation, true, "the probe did not fire inside the edit")
        XCTAssertGreaterThan(
            JinLayoutCostCounters.midEditMeasurements,
            fallbacksBefore,
            "the probe was answered by a layout manager instead of the isolated stack"
        )
        // And it is the height of the text that is LANDING, not of the text it
        // replaced — the apply records its baseline before writing exactly so
        // this answer is usable.
        XCTAssertEqual(
            probed ?? 0,
            liveHeight(replacement, width: 260),
            accuracy: 0.5,
            "the mid-edit answer disagrees with the live measurement — a wrong height here is a "
                + "clipped or gapped row, which is what this whole path exists to avoid"
        )
        // The edit still landed intact.
        XCTAssertEqual(view.attributedString().string, replacement.string)
    }

    /// An edit made WITHOUT going through the view's apply paths, so the depth
    /// guard is not armed — only the storage's own pending-edit state and the
    /// not-yet-notified shadow manager stand between us and the crash.
    func testMeasuringFromInsideAForeignEditIsStillCaught() {
        let (view, probe) = makeView(prose("original", paragraphs: 24), liveWidth: 420, probeWidth: 300)
        guard let storage = view.textStorage else { return XCTFail("no text storage") }

        var sawMutationFlag: Bool?
        var probed: CGFloat?
        probe.onEdited = { [weak view] in
            guard let view, probed == nil else { return }
            sawMutationFlag = view.isMutatingTextStorage
            probed = view.computeHeight(forWidth: 260)
        }

        let fallbacksBefore = JinLayoutCostCounters.midEditMeasurements
        storage.setAttributedString(prose("foreign", paragraphs: 4))

        XCTAssertEqual(sawMutationFlag, false, "this case is supposed to bypass the depth guard")
        XCTAssertGreaterThan(
            JinLayoutCostCounters.midEditMeasurements,
            fallbacksBefore,
            "a not-yet-notified shadow manager was asked to lay out"
        )
        XCTAssertGreaterThan(probed ?? 0, 0)
    }

    /// An attribute-only edit — what the selection aggregator does when it
    /// paints highlights. It changes no characters, so the per-manager
    /// length bookkeeping reads "in sync" and the depth guard is not armed;
    /// only `NSTextStorage.editedMask` says the storage is mid-edit. TextKit
    /// refuses glyph generation just the same.
    func testMeasuringFromInsideAnAttributeOnlyEditIsStillCaught() {
        let (view, probe) = makeView(prose("original", paragraphs: 24), liveWidth: 420, probeWidth: 300)
        guard let storage = view.textStorage else { return XCTFail("no text storage") }

        var lengthsAgreedDuringProbe: Bool?
        var probed: CGFloat?
        probe.onEdited = { [weak view] in
            guard let view, probed == nil else { return }
            let live = view.layoutManager as? JinMarkdownLayoutManager
            lengthsAgreedDuringProbe = live?.jinIsStaleRelativeToStorage == false
            probed = view.computeHeight(forWidth: 260)
        }

        let fallbacksBefore = JinLayoutCostCounters.midEditMeasurements
        storage.addAttribute(
            .backgroundColor,
            value: NSColor.yellow,
            range: NSRange(location: 0, length: min(12, storage.length))
        )

        XCTAssertEqual(
            lengthsAgreedDuringProbe,
            true,
            "this case is supposed to be invisible to the length-based staleness check"
        )
        XCTAssertGreaterThan(
            JinLayoutCostCounters.midEditMeasurements,
            fallbacksBefore,
            "an attribute-only edit was allowed to drive glyph generation"
        )
        XCTAssertGreaterThan(probed ?? 0, 0)
    }

    /// `naturalWidth` shares the probe path (code blocks size their unwrapped
    /// width through it) and must be guarded identically.
    func testNaturalWidthFromInsideAnEditDoesNotDriveTheLayoutManagers() {
        let (view, probe) = makeView(attributed("one short line"), liveWidth: 420, probeWidth: 300)

        var probed: CGFloat?
        probe.onEdited = { [weak view] in
            guard let view, probed == nil else { return }
            probed = view.naturalWidth(maxWidth: 10_000)
        }

        let fallbacksBefore = JinLayoutCostCounters.midEditMeasurements
        view.setScrubbedAttributedString(attributed("a different single line of text"))

        XCTAssertGreaterThan(JinLayoutCostCounters.midEditMeasurements, fallbacksBefore)
        XCTAssertGreaterThan(probed ?? 0, 0)
        XCTAssertLessThan(probed ?? .greatestFiniteMagnitude, 9_000, "reported the container, not the text")
    }

    // MARK: - Applying from inside an edit

    /// The other half of the crash: SwiftUI re-running `updateNSView` from
    /// inside the first apply's notification fan-out, which nested a second
    /// `replaceCharactersInRange:` inside the first one. The second apply must
    /// be queued, not nested — and must still land.
    func testReentrantApplyIsDeferredAndStillLands() {
        let (view, probe) = makeView(attributed("第一版内容"), liveWidth: 420, probeWidth: 300)

        let second = attributed("第二版内容，更长一些的替换文本")
        var mode: JinMessageTextView.ApplyMode?
        var storageLengthDuringProbe: Int?
        probe.onEdited = { [weak view] in
            guard let view, mode == nil else { return }
            storageLengthDuringProbe = view.textStorage?.length
            mode = view.applyAttributedStringPreferringIncremental(second)
        }

        view.setScrubbedAttributedString(attributed("中间版本"))

        XCTAssertEqual(mode, .deferred, "the re-entrant apply wrote into a storage that was mid-edit")
        XCTAssertEqual(
            storageLengthDuringProbe,
            4,
            "the outer edit had not completed when the re-entrant apply arrived"
        )
        XCTAssertEqual(
            view.attributedString().string,
            second.string,
            "the deferred apply was dropped instead of replayed"
        )
    }

    /// Highlight painting goes through the same guard: it is reached from
    /// `AttributedTextBlock.updateNSView` via the aggregator's `register`, so
    /// it lands in the same re-entrant frame.
    func testReentrantStorageMutationIsDeferredAndStillRuns() {
        let (view, probe) = makeView(attributed("需要高亮的一段文本"), liveWidth: 420, probeWidth: 300)

        var ranDuringEdit: Bool?
        var painted = false
        probe.onEdited = { [weak view] in
            guard let view, ranDuringEdit == nil else { return }
            ranDuringEdit = false
            view.performStorageMutation { storage in
                ranDuringEdit = true
                painted = true
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.yellow,
                    range: NSRange(location: 0, length: min(3, storage.length))
                )
            }
            XCTAssertEqual(ranDuringEdit, false, "the mutation ran nested inside the outer edit")
        }

        view.setScrubbedAttributedString(attributed("换过的一段文本内容"))

        XCTAssertTrue(painted, "the deferred mutation was dropped instead of replayed")
        XCTAssertNotNil(
            view.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil),
            "the highlight never reached the storage"
        )
    }

    /// The ordering contract every deferred mutation has to be written
    /// against: the drain replays the pending content apply FIRST, so a
    /// mutation queued before it observes a storage that may have changed
    /// length underneath it. Anything computing ranges outside the closure
    /// must clamp inside it.
    func testDeferredMutationSeesTheReplayedContentNotTheOneItWasQueuedAgainst() {
        let (view, probe) = makeView(attributed("一段很长很长的原始文本内容"), liveWidth: 420, probeWidth: 300)
        let lengthWhenQueued = view.textStorage?.length ?? 0
        XCTAssertGreaterThan(lengthWhenQueued, 6)

        let short = attributed("短文本")
        var lengthWhenReplayed: Int?
        var queued = false
        probe.onEdited = { [weak view] in
            guard let view, !queued else { return }
            queued = true
            view.performStorageMutation { storage in
                lengthWhenReplayed = storage.length
            }
            _ = view.applyAttributedStringPreferringIncremental(short)
        }

        view.setScrubbedAttributedString(attributed("中间版本的文本"))

        XCTAssertEqual(view.attributedString().string, short.string)
        XCTAssertEqual(
            lengthWhenReplayed,
            short.length,
            "the deferred mutation ran against a different storage than the drain finished with"
        )
        XCTAssertLessThan(
            lengthWhenReplayed ?? .max,
            lengthWhenQueued,
            "this test is only meaningful if the replayed content is shorter"
        )
    }

    /// `SelectionAggregator` derives highlight ranges from the block model,
    /// which the deferral above can leave describing longer text than the
    /// storage holds. Painting past the end raises an out-of-range ObjC
    /// exception — the same crash class, one frame over.
    func testHighlightPaintingClampsToTheLiveStorageLength() {
        let messageID = UUID()
        let anchorID = "anchor"
        let blockID = UUID()
        let blockText = "一段完整的原始文本内容"

        let aggregator = SelectionAggregator(
            messageID: messageID,
            anchorID: anchorID,
            actions: .none,
            blocks: [
                SelectionAggregator.BlockOffsetInfo(id: blockID, offsetInAnchor: 0, plainText: blockText)
            ],
            persistedHighlights: [
                MessageHighlightSnapshot(
                    messageID: messageID,
                    anchorID: anchorID,
                    selectedText: blockText,
                    startOffset: 0,
                    endOffset: blockText.utf16.count,
                    colorStyle: .readerYellow
                )
            ]
        )

        // The view already holds a SHORTER string than the block model — what
        // a replayed apply leaves behind.
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(attributed("短"))
        aggregator.register(blockID: blockID, textView: view)

        XCTAssertEqual(view.textStorage?.length, 1)
        XCTAssertNotNil(
            view.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil),
            "the highlight was skipped entirely instead of being clamped"
        )
    }

    // MARK: - No cost in the steady state

    /// The guards must not put the ordinary paths on the isolated stack — that
    /// would reintroduce the per-probe full-text copy the shadow managers
    /// exist to avoid.
    func testQuiescentProbesNeverFallBackToTheIsolatedStack() {
        let view = JinMessageTextView()
        view.setScrubbedAttributedString(prose("steady", paragraphs: 20))
        view.setFrameSize(NSSize(width: 520, height: 10))
        view.layoutSubtreeIfNeeded()

        let fallbacksBefore = JinLayoutCostCounters.midEditMeasurements
        let copiesBefore = JinTextMeasurementStack.copyCount
        for width in [520.0, 300.0, 760.0, 520.0, 180.0] as [CGFloat] {
            _ = view.computeHeight(forWidth: width)
            _ = view.naturalWidth(maxWidth: width)
        }

        XCTAssertEqual(JinLayoutCostCounters.midEditMeasurements, fallbacksBefore)
        XCTAssertEqual(JinTextMeasurementStack.copyCount, copiesBefore)
    }
}
