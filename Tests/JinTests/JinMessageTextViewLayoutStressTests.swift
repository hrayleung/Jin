import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// Stress harness for the TextKit 1 measurement path, after a production crash
/// whose only app frame was
/// `JinMessageTextView.computeHeight(forWidth:)` → `NSLayoutManager.ensureLayout`
/// → `_fillLayoutHoleAtIndex:` → `-[NSRLEArray objectAtRunIndex:length:]`
/// (an ObjC range exception), raised inside the window's Auto Layout
/// `updateConstraints` pass.
///
/// That shape means the layout manager walked a character index the text
/// storage no longer has — i.e. measurement ran against a storage/container
/// pair that changed underneath it. The measurement path mutates the LIVE
/// container for off-width probes, so this hammers exactly that combination:
/// storage edits, width changes, off-width probes and real constraint passes
/// interleaved. An ObjC exception here aborts the test process, which is the
/// signal.
@MainActor
final class JinMessageTextViewLayoutStressTests: XCTestCase {

    private func markdownAttributed(_ text: String, codeRuns: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        guard codeRuns, result.length > 40 else { return result }
        // Decorative runs so JinMarkdownLayoutManager's delegate + background
        // drawing participate (its line-break delegate runs *during* layout).
        var location = 10
        while location + 12 < result.length {
            result.addAttributes(
                [
                    .jinInlineCodeBackground: NSColor.gray.withAlphaComponent(0.2),
                    .jinInlineCodeBorder: NSColor.gray,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                ],
                range: NSRange(location: location, length: 8)
            )
            result.addAttribute(
                .jinBlockQuoteDepth,
                value: NSNumber(value: 1),
                range: NSRange(location: location + 8, length: 4)
            )
            location += 97
        }
        return result
    }

    private func hostedView() -> (JinMessageTextView, NSWindow) {
        let view = JinMessageTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 1_200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 1_200))
        window.contentView = container
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        return (view, window)
    }

    /// Storage growth (streaming) interleaved with off-width probes and real
    /// constraint passes — the production sequence.
    func testStreamingAppendsWithOffWidthProbesAndConstraintPasses() {
        let (view, window) = hostedView()
        var text = "Streaming prefix with `code` and a quote marker. "
        view.setScrubbedAttributedString(markdownAttributed(text))
        window.contentView?.layoutSubtreeIfNeeded()

        for step in 0..<120 {
            text += "第\(step)段：resolution-dependent DiT scaling and different DiT/VAE behavior, "
                + "plus `inline code` and a longer clause to force re-wrapping. "
            _ = view.applyAttributedStringPreferringIncremental(markdownAttributed(text))

            // SwiftUI probes min/ideal/max — all off the live width.
            _ = view.computeHeight(forWidth: 320)
            _ = view.computeHeight(forWidth: 10_000)
            _ = view.naturalWidth(maxWidth: 10_000)
            _ = view.computeHeight(forWidth: 640 + CGFloat(step % 7))

            // Real constraint pass: this is the stack the crash came from.
            view.invalidateIntrinsicContentSize()
            window.contentView?.updateConstraintsForSubtreeIfNeeded()
            _ = view.intrinsicContentSize
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(view.computeHeight(forWidth: 640), 0)
    }

    /// Full replacements that SHRINK the storage while probes and constraint
    /// passes run. A layout hole left pointing past the new end is precisely
    /// the "index beyond bounds" the crash raised.
    func testShrinkingReplacementsBetweenProbesAndConstraintPasses() {
        let (view, window) = hostedView()
        let long = String(
            repeating: "长文本段落 with `code` runs and enough words to wrap several times. ",
            count: 60
        )
        for step in 0..<80 {
            let shrinking = String(long.prefix(max(20, long.count - step * 37)))
            view.setScrubbedAttributedString(markdownAttributed(shrinking))
            _ = view.computeHeight(forWidth: 10_000)
            _ = view.naturalWidth(maxWidth: 10_000)
            view.invalidateIntrinsicContentSize()
            window.contentView?.updateConstraintsForSubtreeIfNeeded()
            _ = view.intrinsicContentSize
            _ = view.computeHeight(forWidth: 280)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(view.computeHeight(forWidth: 500), 0)
    }

    /// Frame-width changes (window resize / column re-wrap) interleaved with
    /// off-width probes: the live container is being driven from two
    /// directions at once.
    func testFrameWidthChangesInterleavedWithOffWidthProbes() {
        let (view, window) = hostedView()
        view.setScrubbedAttributedString(
            markdownAttributed(String(repeating: "wrap probe 段落 with `code`. ", count: 200))
        )
        for step in 0..<120 {
            let width = 300 + CGFloat((step * 53) % 600)
            view.setFrameSize(NSSize(width: width, height: view.frame.height))
            _ = view.computeHeight(forWidth: width)
            _ = view.computeHeight(forWidth: 10_000)
            _ = view.naturalWidth(maxWidth: 4_000)
            view.invalidateIntrinsicContentSize()
            window.contentView?.updateConstraintsForSubtreeIfNeeded()
            _ = view.intrinsicContentSize
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(view.computeHeight(forWidth: 600), 0)
    }

    /// Selection/highlight attributes painted into storage between probes —
    /// the aggregator does this on live views.
    func testAttributePaintingBetweenProbes() {
        let (view, window) = hostedView()
        let base = String(repeating: "highlight target 段落 with `code` runs. ", count: 120)
        view.setScrubbedAttributedString(markdownAttributed(base))
        window.contentView?.layoutSubtreeIfNeeded()

        for step in 0..<120 {
            guard let storage = view.textStorage, storage.length > 60 else { break }
            let location = (step * 29) % (storage.length - 40)
            storage.beginEditing()
            storage.addAttribute(
                .backgroundColor,
                value: NSColor.yellow.withAlphaComponent(0.4),
                range: NSRange(location: location, length: 30)
            )
            storage.endEditing()
            _ = view.computeHeight(forWidth: 10_000)
            _ = view.naturalWidth(maxWidth: 10_000)
            view.invalidateIntrinsicContentSize()
            window.contentView?.updateConstraintsForSubtreeIfNeeded()
            _ = view.intrinsicContentSize
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(view.computeHeight(forWidth: 600), 0)
    }
}
