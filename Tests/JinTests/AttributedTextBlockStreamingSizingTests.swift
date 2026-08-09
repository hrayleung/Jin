import AppKit
import SwiftUI
import XCTest
@testable import Jin

/// `AttributedTextBlock.sizeThatFits` must NOT write into the live text view
/// (a storage edit during AppKit's layout cycle corrupts TextKit and crashed
/// the app twice while streaming). It measures the pending string on the
/// isolated stack instead — which is only correct if the height it reports is
/// the height the view ends up with once `updateNSView` applies that string.
///
/// This drives the real SwiftUI representable through `NSHostingView` with a
/// growing streaming tail and checks exactly that, plus that the host's own
/// reported height tracks the content.
@MainActor
final class AttributedTextBlockStreamingSizingTests: XCTestCase {

    private let width: CGFloat = 640

    private func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
    }

    private func firstTextView(in view: NSView) -> JinMessageTextView? {
        if let match = view as? JinMessageTextView { return match }
        for subview in view.subviews {
            if let match = firstTextView(in: subview) { return match }
        }
        return nil
    }

    func testStreamingTailHeightsMatchWhatTheViewEndsUpWith() {
        var text = "Streaming prefix. "
        var signature: UInt64 = 0

        let host = NSHostingView(
            rootView: AnyView(
                AttributedTextBlock(attributedString: attributed(text), contentSignature: signature)
                    .frame(width: width)
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        host.layoutSubtreeIfNeeded()

        var previousHeight: CGFloat = 0
        for step in 0..<40 {
            text += "第\(step)段：resolution-dependent scaling with a clause long enough to wrap. "
            signature &+= 1
            host.rootView = AnyView(
                AttributedTextBlock(attributedString: attributed(text), contentSignature: signature)
                    .frame(width: width)
            )
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()

            let hostHeight = host.fittingSize.height
            guard let textView = firstTextView(in: host) else {
                return XCTFail("no JinMessageTextView hosted")
            }
            // What the live view — now carrying the applied string — measures.
            let liveHeight = textView.computeHeight(forWidth: width)

            XCTAssertEqual(
                hostHeight,
                liveHeight,
                accuracy: 1,
                "step \(step): SwiftUI sized the block at \(hostHeight) but the applied text needs "
                    + "\(liveHeight) — a row sized from a stale/mismatched measurement clips or gaps"
            )
            XCTAssertGreaterThanOrEqual(
                hostHeight,
                previousHeight,
                "step \(step): a growing streaming tail must never shrink the block"
            )
            previousHeight = hostHeight
        }
        XCTAssertGreaterThan(previousHeight, 100)
    }

    /// Measuring a not-yet-applied string must leave the live view untouched:
    /// same storage, same container width, same wrap.
    func testMeasuringPendingContentLeavesTheLiveViewUntouched() {
        let host = NSHostingView(
            rootView: AnyView(
                AttributedTextBlock(attributedString: attributed("original content here"), contentSignature: 1)
                    .frame(width: width)
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        host.layoutSubtreeIfNeeded()

        guard let textView = firstTextView(in: host) else {
            return XCTFail("no JinMessageTextView hosted")
        }
        let storageBefore = textView.attributedString().string
        let containerBefore = textView.textContainer?.size.width ?? 0

        // Ask SwiftUI to size a DIFFERENT string without letting it commit an
        // update: `sizeThatFits` runs during this layout query.
        let probe = NSHostingView(
            rootView: AnyView(
                AttributedTextBlock(
                    attributedString: attributed(String(repeating: "pending replacement text ", count: 50)),
                    contentSignature: 2
                )
                .frame(width: width)
            )
        )
        _ = probe.fittingSize

        XCTAssertEqual(textView.attributedString().string, storageBefore)
        XCTAssertEqual(textView.textContainer?.size.width ?? 0, containerBefore, accuracy: 0.5)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
    }
}
