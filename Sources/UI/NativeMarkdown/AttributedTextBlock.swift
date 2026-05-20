import AppKit
import SwiftUI

/// `NSViewRepresentable` wrapping `JinMessageTextView`. When given a
/// `SelectionAggregator` + `blockID`, the underlying NSTextView reports its
/// selection through the aggregator for quote/highlight UX.
struct AttributedTextBlock: NSViewRepresentable {
    let attributedString: NSAttributedString
    let links: [LinkRange]
    let blockID: UUID?
    let aggregator: SelectionAggregator?

    init(
        attributedString: NSAttributedString,
        links: [LinkRange] = [],
        blockID: UUID? = nil,
        aggregator: SelectionAggregator? = nil
    ) {
        self.attributedString = attributedString
        self.links = links
        self.blockID = blockID
        self.aggregator = aggregator
    }

    func makeCoordinator() -> Coordinator { Coordinator(links: links) }

    func makeNSView(context: Context) -> JinMessageTextView {
        let view = JinMessageTextView()
        view.delegate = context.coordinator
        view.aggregator = aggregator
        view.blockID = blockID
        applyAttributedString(to: view)
        registerWithAggregator(view: view)
        return view
    }

    func updateNSView(_ nsView: JinMessageTextView, context: Context) {
        context.coordinator.links = links
        let aggregatorChanged = nsView.aggregator !== aggregator
        let blockChanged = nsView.blockID != blockID
        nsView.aggregator = aggregator
        nsView.blockID = blockID
        if !nsView.attributedString().isEqual(to: attributedString) {
            applyAttributedString(to: nsView)
            registerWithAggregator(view: nsView)
        } else if aggregatorChanged || blockChanged {
            registerWithAggregator(view: nsView)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: JinMessageTextView,
        context: Context
    ) -> CGSize? {
        if !nsView.attributedString().isEqual(to: attributedString) {
            applyAttributedString(to: nsView)
            registerWithAggregator(view: nsView)
        }

        // Two layout phases:
        //
        //  1. SwiftUI ideal-size pass with `proposal.width == nil` — return
        //     `nil` so SwiftUI treats us as flexible-width (matching the
        //     behaviour of `SwiftUI.Text`). Returning a concrete
        //     "unconstrained natural width" here (`naturalWidth(maxWidth:
        //     10_000)`) is the bug that caused blockquote prose to render
        //     past the bubble's right edge: SwiftUI honoured the reported
        //     1000+pt width as the row's ideal and laid out at that
        //     unwrapped width even when the parent column was 700pt wide.
        //  2. SwiftUI definite-width pass with `proposal.width == W` — lay
        //     out at W and report the resulting wrapped height. The text
        //     container's `widthTracksTextView = true` keeps the
        //     NSTextView's wrap point in sync once SwiftUI sets our frame.
        guard let proposedWidth = proposal.width, proposedWidth.isFinite, proposedWidth > 0 else {
            return nil
        }

        let height = nsView.computeHeight(forWidth: proposedWidth)
        return CGSize(width: max(1, proposedWidth), height: max(1, height))
    }

    @MainActor
    private func registerWithAggregator(view: JinMessageTextView) {
        guard let aggregator, let blockID else { return }
        aggregator.register(blockID: blockID, textView: view)
    }

    private func applyAttributedString(to view: JinMessageTextView) {
        view.textStorage?.setAttributedString(attributedString)
        view.invalidateHeightCache()
        view.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var links: [LinkRange]

        init(links: [LinkRange]) {
            self.links = links
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}
