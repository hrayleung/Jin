import SwiftUI

struct ConstrainedWidth: Layout {
    let maxWidth: CGFloat

    init(_ maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let proposedWidth = min(maxWidth, proposal.width ?? maxWidth)
        let size = subview.sizeThatFits(
            ProposedViewSize(
                width: proposedWidth,
                height: proposal.height
            )
        )
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }

        let proposedWidth = min(maxWidth, bounds.width)
        let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: bounds.height))
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
    }
}

