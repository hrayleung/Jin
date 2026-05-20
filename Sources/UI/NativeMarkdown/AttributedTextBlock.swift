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

        let proposedWidth = proposal.width
        let isConstrained: Bool
        let layoutWidth: CGFloat

        if let w = proposedWidth, w.isFinite, w > 0 {
            isConstrained = true
            layoutWidth = w
        } else {
            // SwiftUI is asking for our natural size — measure at a generous
            // width and return the actually used width.
            isConstrained = false
            layoutWidth = 10_000
        }

        let height = nsView.computeHeight(forWidth: layoutWidth)
        let returnWidth: CGFloat
        if isConstrained {
            returnWidth = layoutWidth
        } else {
            returnWidth = nsView.naturalWidth(maxWidth: layoutWidth)
        }
        return CGSize(width: max(1, returnWidth), height: max(1, height))
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
