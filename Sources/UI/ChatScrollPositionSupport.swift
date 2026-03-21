import Foundation
import CoreGraphics

enum ChatScrollPositionSupport {
    struct MessageFrame: Equatable {
        let id: UUID
        let minY: CGFloat
        let maxY: CGFloat
    }

    struct RestorationPlan: Equatable {
        let messageRenderLimit: Int
        let pendingRestoreMessageID: UUID?
        let isPinnedToBottom: Bool
        let clearsStoredAnchor: Bool
    }

    static func storedMessageID(
        topVisibleMessageID: UUID?,
        renderedMessageIDs: [UUID]
    ) -> UUID? {
        return topVisibleMessageID ?? renderedMessageIDs.first
    }

    static func restorationPlan(
        savedMessageID: UUID?,
        messageIDs: [UUID],
        currentRenderLimit: Int,
        pageSize: Int
    ) -> RestorationPlan {
        guard let savedMessageID else {
            return RestorationPlan(
                messageRenderLimit: currentRenderLimit,
                pendingRestoreMessageID: nil,
                isPinnedToBottom: true,
                clearsStoredAnchor: false
            )
        }

        guard let targetIndex = messageIDs.firstIndex(of: savedMessageID) else {
            return RestorationPlan(
                messageRenderLimit: currentRenderLimit,
                pendingRestoreMessageID: nil,
                isPinnedToBottom: true,
                clearsStoredAnchor: !messageIDs.isEmpty
            )
        }

        let distanceFromEnd = messageIDs.count - targetIndex
        let requiredRenderLimit: Int
        if distanceFromEnd > currentRenderLimit {
            requiredRenderLimit = min(messageIDs.count, distanceFromEnd + pageSize)
        } else {
            requiredRenderLimit = currentRenderLimit
        }

        return RestorationPlan(
            messageRenderLimit: requiredRenderLimit,
            pendingRestoreMessageID: savedMessageID,
            isPinnedToBottom: false,
            clearsStoredAnchor: false
        )
    }

    static func topVisibleMessageID(
        messageFrames: [MessageFrame],
        viewportHeight: CGFloat
    ) -> UUID? {
        guard viewportHeight > 0 else { return nil }

        return messageFrames
            .filter { $0.maxY > 0 && $0.minY < viewportHeight }
            .sorted {
                if abs($0.minY - $1.minY) > 0.5 {
                    return $0.minY < $1.minY
                }
                return $0.maxY < $1.maxY
            }
            .first?
            .id
    }

    static func isPinnedToBottom(
        bottomAnchorMaxY: CGFloat?,
        viewportHeight: CGFloat,
        bottomTolerance: CGFloat
    ) -> Bool? {
        guard let bottomAnchorMaxY, viewportHeight > 0 else { return nil }
        let distanceFromBottom = max(0, bottomAnchorMaxY - viewportHeight)
        return distanceFromBottom <= max(80, bottomTolerance)
    }
}
