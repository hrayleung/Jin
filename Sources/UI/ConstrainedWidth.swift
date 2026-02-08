import SwiftUI

struct ConstrainedWidth: Layout {
    let maxWidth: CGFloat

    struct Cache {
        var measuredSize: CGSize = .zero
        var measuredWidth: CGFloat = -1
    }

    init(_ maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let proposedWidth = min(maxWidth, proposal.width ?? maxWidth)
        let measured = subview.sizeThatFits(
            ProposedViewSize(
                width: proposedWidth,
                height: proposal.height
            )
        )

        let size = CGSize(width: min(measured.width, proposedWidth), height: measured.height)
        cache.measuredSize = size
        cache.measuredWidth = proposedWidth
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard let subview = subviews.first else { return }

        let proposedWidth = min(maxWidth, bounds.width)
        let targetSize: CGSize

        if abs(cache.measuredWidth - proposedWidth) < 0.5, cache.measuredSize != .zero {
            targetSize = cache.measuredSize
        } else {
            let measured = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            let normalized = CGSize(width: min(measured.width, proposedWidth), height: measured.height)
            cache.measuredSize = normalized
            cache.measuredWidth = proposedWidth
            targetSize = normalized
        }

        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: proposedWidth, height: targetSize.height)
        )
    }
}
