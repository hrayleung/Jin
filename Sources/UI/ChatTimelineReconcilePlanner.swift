import Foundation

/// Pure old→new row-identity diff decision for the recycling timeline.
/// Split from the controller so the mutation choice is testable without a
/// table view.
///
/// Branch order mirrors the controller's historical checks exactly
/// (identical / in-place / append / prepend), then `batchDiff` covers every
/// remaining shape as removals + insertions before the `fullReload` fallback.
/// The shape that motivated it: sending in a window-capped conversation
/// slides the render window (head identities drop, tail appends), which used
/// to match nothing and tear down every realized cell via reloadData.
enum ChatTimelineReconcilePlanner {
    /// Above this many row mutations a reloadData is cheaper than a batch,
    /// and a diff that large means wholesale identity churn anyway.
    /// (Load-earlier pages insert `messageRenderPageSize` = 40 rows.)
    static let maxBatchMutations = 64

    enum Plan: Equatable {
        case identical
        /// Same count, some identities differ positionally (commonly the
        /// streaming row replaced by the finished message at the tail).
        case reloadInPlace(changed: IndexSet)
        case appendTail(inserted: Range<Int>)
        case prependHead(inserted: Range<Int>)
        /// Removals are OLD-coordinate offsets, insertions NEW-coordinate —
        /// `CollectionDifference`'s convention, which is also exactly
        /// NSTableView's batch contract inside beginUpdates/endUpdates
        /// (removeRows takes pre-update indexes, insertRows post-removal).
        case batchDiff(removals: IndexSet, insertions: IndexSet)
        case fullReload
    }

    static func plan(oldIDs: [String], newIDs: [String]) -> Plan {
        if oldIDs == newIDs { return .identical }

        if oldIDs.count == newIDs.count {
            let changed = IndexSet((0..<newIDs.count).filter { oldIDs[$0] != newIDs[$0] })
            if !changed.isEmpty { return .reloadInPlace(changed: changed) }
        }

        if newIDs.count > oldIDs.count, Array(newIDs.prefix(oldIDs.count)) == oldIDs {
            return .appendTail(inserted: oldIDs.count..<newIDs.count)
        }

        if newIDs.count > oldIDs.count, Array(newIDs.suffix(oldIDs.count)) == oldIDs {
            return .prependHead(inserted: 0..<(newIDs.count - oldIDs.count))
        }

        // Chat rows never reorder, so a plain difference (no move inference)
        // is minimal: shared identities keep their realized cells.
        let difference = newIDs.difference(from: oldIDs)
        guard difference.count <= maxBatchMutations else { return .fullReload }

        var removals = IndexSet()
        var insertions = IndexSet()
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removals.insert(offset)
            case .insert(let offset, _, _):
                insertions.insert(offset)
            }
        }
        return .batchDiff(removals: removals, insertions: insertions)
    }
}
