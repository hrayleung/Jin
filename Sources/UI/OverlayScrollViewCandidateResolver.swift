import AppKit

@MainActor
struct OverlayScrollViewCandidateResolver {
    private let maxAncestorDepth = 12

    func resolveBestCandidate(for probeView: NSView) -> NSScrollView? {
        if let enclosingScrollView = probeView.enclosingScrollView {
            return enclosingScrollView
        }

        let coordinateSpaceRoot = rootView(for: probeView)
        let candidates = collectCandidates(around: probeView)
        guard !candidates.isEmpty else { return nil }

        let probeRect = probeView.convert(probeView.bounds, to: coordinateSpaceRoot)

        return candidates.max { lhs, rhs in
            compare(lhs, rhs, probeRect: probeRect, coordinateSpaceRoot: coordinateSpaceRoot) == .orderedAscending
        }?.scrollView
    }

    private func collectCandidates(around probeView: NSView) -> [OverlayScrollViewCandidate] {
        var candidates: [OverlayScrollViewCandidate] = []
        var seen = Set<ObjectIdentifier>()
        var current: NSView = probeView
        var ancestorDepth = 0

        while ancestorDepth <= maxAncestorDepth, let parent = current.superview {
            if let scrollView = parent as? NSScrollView {
                appendCandidate(
                    scrollView,
                    ancestorDepth: ancestorDepth,
                    to: &candidates,
                    seen: &seen,
                    relativeTo: probeView
                )
            }

            for sibling in parent.subviews where sibling !== current {
                appendDescendantCandidates(
                    in: sibling,
                    ancestorDepth: ancestorDepth,
                    to: &candidates,
                    seen: &seen,
                    relativeTo: probeView
                )
            }

            current = parent
            ancestorDepth += 1
        }

        return candidates
    }

    private func appendDescendantCandidates(
        in rootView: NSView,
        ancestorDepth: Int,
        to candidates: inout [OverlayScrollViewCandidate],
        seen: inout Set<ObjectIdentifier>,
        relativeTo probeView: NSView
    ) {
        var queue = [rootView]

        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? NSScrollView {
                appendCandidate(
                    scrollView,
                    ancestorDepth: ancestorDepth,
                    to: &candidates,
                    seen: &seen,
                    relativeTo: probeView
                )
                continue
            }

            queue.append(contentsOf: view.subviews)
        }
    }

    private func appendCandidate(
        _ scrollView: NSScrollView,
        ancestorDepth: Int,
        to candidates: inout [OverlayScrollViewCandidate],
        seen: inout Set<ObjectIdentifier>,
        relativeTo probeView: NSView
    ) {
        let identifier = ObjectIdentifier(scrollView)
        guard seen.insert(identifier).inserted else { return }
        candidates.append(
            OverlayScrollViewCandidate(
                scrollView: scrollView,
                ancestorDepth: ancestorDepth
            )
        )
    }

    private func rootView(for probeView: NSView) -> NSView {
        var current = probeView
        while let parent = current.superview {
            current = parent
        }
        return current
    }

    private func compare(
        _ lhs: OverlayScrollViewCandidate,
        _ rhs: OverlayScrollViewCandidate,
        probeRect: NSRect,
        coordinateSpaceRoot: NSView
    ) -> ComparisonResult {
        let lhsIntersection = lhs.intersectionArea(with: probeRect, in: coordinateSpaceRoot)
        let rhsIntersection = rhs.intersectionArea(with: probeRect, in: coordinateSpaceRoot)
        if lhsIntersection != rhsIntersection {
            return lhsIntersection < rhsIntersection ? .orderedAscending : .orderedDescending
        }

        let lhsDistance = lhs.distanceSquared(to: probeRect, in: coordinateSpaceRoot)
        let rhsDistance = rhs.distanceSquared(to: probeRect, in: coordinateSpaceRoot)
        if lhsDistance != rhsDistance {
            return lhsDistance > rhsDistance ? .orderedAscending : .orderedDescending
        }

        if lhs.ancestorDepth != rhs.ancestorDepth {
            return lhs.ancestorDepth > rhs.ancestorDepth ? .orderedAscending : .orderedDescending
        }

        return .orderedSame
    }
}

@MainActor
private struct OverlayScrollViewCandidate {
    let scrollView: NSScrollView
    let ancestorDepth: Int

    func intersectionArea(with otherRect: NSRect, in coordinateSpaceRoot: NSView) -> CGFloat {
        let candidateRect = rect(in: coordinateSpaceRoot)
        return candidateRect.intersection(otherRect).area
    }

    func distanceSquared(to otherRect: NSRect, in coordinateSpaceRoot: NSView) -> CGFloat {
        let candidateRect = rect(in: coordinateSpaceRoot)
        let dx = candidateRect.midX - otherRect.midX
        let dy = candidateRect.midY - otherRect.midY
        return (dx * dx) + (dy * dy)
    }

    private func rect(in coordinateSpaceRoot: NSView) -> NSRect {
        scrollView.convert(scrollView.bounds, to: coordinateSpaceRoot)
    }
}

private extension NSRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}
