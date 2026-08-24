import Foundation

/// Surviving same-identity rows are NOT reconfigured by `batchDiff` /
/// `reloadInPlace` / `appendTail` — those mutations only touch inserted or
/// identity-changed indexes. An in-place user-message edit that also deletes
/// the following assistant turn therefore left the edited cell mounted as
/// the empty `DroppableTextEditor` until some later epoch reload.
enum ChatTimelineSurvivingRowReloadSupport {
    static func identitiesNeedingReload(
        old: [ChatTimelineRow],
        new: [ChatTimelineRow],
        previousEditingUserMessageID: UUID?,
        newEditingUserMessageID: UUID?,
        previousStreamingActivityOwnerMessageID: UUID? = nil,
        newStreamingActivityOwnerMessageID: UUID? = nil
    ) -> Set<String> {
        var previousItems: [String: MessageRenderItem] = [:]
        previousItems.reserveCapacity(old.count)
        for row in old {
            if case .message(let item, _) = row {
                previousItems[row.identity] = item
            }
        }

        var identities: Set<String> = []
        for row in new {
            guard case .message(let item, _) = row,
                  let previous = previousItems[row.identity],
                  shouldReload(
                    previous: previous,
                    current: item,
                    previousEditingUserMessageID: previousEditingUserMessageID,
                    newEditingUserMessageID: newEditingUserMessageID
                  ) else {
                continue
            }
            identities.insert(row.identity)
        }

        // The persisted assistant that hosted Connecting is a surviving
        // identity when the streaming row is removed or a follow-up message
        // is appended. Without this reload it keeps the pre-finish snapshot
        // until the user leaves and re-enters the conversation.
        if previousStreamingActivityOwnerMessageID != newStreamingActivityOwnerMessageID {
            insertMessageIdentity(previousStreamingActivityOwnerMessageID, into: &identities)
            insertMessageIdentity(newStreamingActivityOwnerMessageID, into: &identities)
        }
        return identities
    }

    static func shouldReload(
        previous: MessageRenderItem,
        current: MessageRenderItem,
        previousEditingUserMessageID: UUID?,
        newEditingUserMessageID: UUID?
    ) -> Bool {
        let wasEditing = previousEditingUserMessageID == current.id
        let isEditing = newEditingUserMessageID == current.id
        return wasEditing != isEditing
            || previous.copyText != current.copyText
            || previous.timestamp != current.timestamp
            || previous.canDeleteResponse != current.canDeleteResponse
            || previous.perMessageMCPServerNames != current.perMessageMCPServerNames
            || previous.renderedBlocks.count != current.renderedBlocks.count
    }

    private static func insertMessageIdentity(_ messageID: UUID?, into identities: inout Set<String>) {
        guard let messageID else { return }
        identities.insert("msg-\(messageID.uuidString)")
    }
}
