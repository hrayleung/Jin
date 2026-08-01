import Foundation

/// Slice policy for the provisional first paint when switching into a large
/// conversation: the async rebuild used to leave the timeline EMPTY until the
/// whole-conversation decode landed. Decoding just the tail is visually
/// complete for that first paint — the table renders only the last
/// `ChatView.initialMessageRenderLimit` (24) messages after a switch anyway —
/// and must stay cheap enough to run synchronously on the main actor, hence
/// the byte budget.
enum ChatRenderProvisionalTailPolicy {
    /// Mirrors `ChatView.initialMessageRenderLimit`.
    static let maxMessages = 24
    /// Total contentData budget for the synchronous decode.
    static let maxTotalBytes = 300_000
    /// A single message beyond this is too big to decode on the main actor —
    /// degrade to today's behavior (blank until the async decode lands).
    static let maxSingleMessageBytes = 2_000_000

    /// The suffix to decode provisionally, in original order. The tail
    /// message is always included when it fits the single-message ceiling,
    /// even if it alone exceeds the total budget — painting the newest
    /// message is the whole point.
    static func tailSlice(of snapshots: [PersistedMessageSnapshot]) -> [PersistedMessageSnapshot] {
        var slice: [PersistedMessageSnapshot] = []
        var totalBytes = 0
        for snapshot in snapshots.reversed() {
            guard slice.count < maxMessages else { break }
            let size = snapshot.contentData.count
            guard size <= maxSingleMessageBytes else { break }
            if !slice.isEmpty, totalBytes + size > maxTotalBytes { break }
            slice.append(snapshot)
            totalBytes += size
        }
        return slice.reversed()
    }
}
