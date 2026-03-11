import SwiftUI

struct ConstrainedWidthCacheInvalidation: Equatable {
    enum Mode: Equatable {
        case automatic
        case version(Int)
    }

    let mode: Mode

    static let automatic = ConstrainedWidthCacheInvalidation(mode: .automatic)

    static func version(_ value: Int) -> ConstrainedWidthCacheInvalidation {
        ConstrainedWidthCacheInvalidation(mode: .version(value))
    }
}

struct ConstrainedWidthContentVersionKey: LayoutValueKey {
    static let defaultValue: ConstrainedWidthCacheInvalidation = .automatic
}

struct ConstrainedWidth: Layout {
    let maxWidth: CGFloat

    struct Cache {
        var measuredSize: CGSize?
        var measuredWidth: CGFloat?
        var invalidation: ConstrainedWidthCacheInvalidation = ConstrainedWidthContentVersionKey.defaultValue
    }

    init(_ maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }

    func makeCache(subviews: Subviews) -> Cache {
        var cache = Cache()
        if let subview = subviews.first {
            cache.invalidation = subview[ConstrainedWidthContentVersionKey.self]
        }
        return cache
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        guard let subview = subviews.first else {
            cache = Cache()
            return
        }
        let invalidation = subview[ConstrainedWidthContentVersionKey.self]

        switch invalidation.mode {
        case .automatic:
            // Preserve SwiftUI's default cache semantics for non-streaming content so
            // ordinary message rows still remeasure when their subtree changes shape.
            cache = makeCache(subviews: subviews)

        case .version:
            guard invalidation != cache.invalidation else { return }
            cache.measuredSize = nil
            cache.measuredWidth = nil
            cache.invalidation = invalidation
        }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let proposedWidth = resolvedWidth(for: proposal.width)
        return measuredSize(for: proposedWidth, subview: subview, cache: &cache)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard let subview = subviews.first else { return }

        let proposedWidth = resolvedWidth(for: bounds.width)
        let targetSize = measuredSize(for: proposedWidth, subview: subview, cache: &cache)

        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: proposedWidth, height: targetSize.height)
        )
    }

    // Avoid SwiftUI's default Layout alignment resolution, which can recurse back into
    // child geometry measurement during rapid streaming updates and hang the main thread.
    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        nil
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        nil
    }

    private func measuredSize(
        for proposedWidth: CGFloat,
        subview: LayoutSubview,
        cache: inout Cache
    ) -> CGSize {
        if let cachedWidth = cache.measuredWidth,
           let cachedSize = cache.measuredSize,
           abs(cachedWidth - proposedWidth) < 0.5 {
            return cachedSize
        }

        guard proposedWidth > 0 else {
            cache.measuredWidth = proposedWidth
            cache.measuredSize = .zero
            return .zero
        }

        let measured = subview.sizeThatFits(
            ProposedViewSize(
                width: proposedWidth,
                height: nil
            )
        )

        let normalized = CGSize(
            width: min(measured.width, proposedWidth),
            height: measured.height
        )
        cache.measuredWidth = proposedWidth
        cache.measuredSize = normalized
        return normalized
    }

    private func resolvedWidth(for proposalWidth: CGFloat?) -> CGFloat {
        let candidate = proposalWidth ?? maxWidth
        guard candidate.isFinite else { return maxWidth }
        return max(0, min(maxWidth, candidate))
    }
}
