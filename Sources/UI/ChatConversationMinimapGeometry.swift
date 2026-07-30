import CoreGraphics
import Foundation

/// Pure math + text shaping behind the conversation minimap — the tick rail
/// that floats over the left edge of the chat.
///
/// "Timeline" in this codebase already means the transcript itself
/// (`ChatTimelineTableController` and friends), so the navigation rail is
/// deliberately named "minimap" throughout.
///
/// Everything here is a value-in/value-out static so it can be unit tested
/// without a view, matching the convention of `ChatTimelineHeightEstimator`
/// and `ChatTimelineScrollCoordinator`.
enum ChatConversationMinimapGeometry {

    /// Vertical distance between two ticks. The rail never squeezes below this
    /// — when there are more turns than fit it shows a sliding window instead,
    /// because crammed-together ticks are neither readable nor clickable.
    static let tickPitch: CGFloat = 15

    static let userExcerptLimit = 140
    static let assistantExcerptLimit = 220

    /// Role label shown above the user excerpt on the hover card.
    static let userRoleLabel = "YOU"

    /// Default role label for the assistant excerpt when the conversation
    /// still uses the generic "Assistant" display name.
    static let defaultAssistantRoleLabel = "ASSISTANT"

    private static let ellipsis = "…"

    /// Formats the assistant role label for the hover card. Generic assistants
    /// render as `ASSISTANT`; named ones keep their display name in uppercase
    /// so the card matches the compact YOU / ASSISTANT visual language.
    static func assistantRoleLabel(displayName: String) -> String {
        guard let custom = customAssistantDisplayName(displayName) else {
            return defaultAssistantRoleLabel
        }
        return custom.uppercased()
    }

    /// Returns a trimmed custom assistant name for UI that should suppress the
    /// generic default (e.g. search-activity provider labels). `nil` covers
    /// blank input and any case/diacritic-insensitive match of "Assistant".
    static func customAssistantDisplayName(_ displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.compare("Assistant", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return nil
        }
        return trimmed
    }

    // MARK: - Turns

    /// One conversation turn: a question and the beginning of its answer.
    ///
    /// `id` is the anchor message the rail scrolls to — the user message, so a
    /// jump lands on the question with the reply flowing in underneath.
    struct Turn: Identifiable, Equatable {
        let id: UUID
        let index: Int
        let userExcerpt: String
        let assistantExcerpt: String
    }

    /// The rail's data: the turns themselves plus a lookup from *any* message
    /// to the turn that contains it. The lookup is what turns the controller's
    /// "top visible message" report into a highlighted tick — the message on
    /// screen is usually the assistant reply, not the turn's anchor.
    struct TurnList: Equatable {
        let turns: [Turn]
        let turnIndexByMessageID: [UUID: Int]

        static let empty = TurnList(turns: [], turnIndexByMessageID: [:])

        func turnIndex(forMessageID id: UUID?) -> Int? {
            guard let id else { return nil }
            return turnIndexByMessageID[id]
        }
    }

    /// Groups a chronologically ordered message list into turns.
    ///
    /// Each user message opens a turn; the first assistant message after it
    /// supplies the reply excerpt. Tool (and system) messages don't open turns —
    /// they are transcript plumbing, not something a user navigates to — but
    /// they do map to the surrounding turn so the active tick doesn't blink out
    /// while one scrolls past. A conversation that opens with assistant
    /// messages (a branch, or a seeded greeting) gets a leading turn with an
    /// empty `userExcerpt` rather than silently dropping those messages.
    static func turnList(from messages: [MessageRenderItem]) -> TurnList {
        var turns: [Turn] = []
        var turnIndexByMessageID: [UUID: Int] = [:]
        turnIndexByMessageID.reserveCapacity(messages.count)

        var anchorID: UUID?
        var userExcerpt = ""
        var assistantExcerpt = ""

        func closeTurn() {
            guard let anchorID else { return }
            turns.append(
                Turn(
                    id: anchorID,
                    index: turns.count,
                    userExcerpt: userExcerpt,
                    assistantExcerpt: assistantExcerpt
                )
            )
            userExcerpt = ""
            assistantExcerpt = ""
        }

        for message in messages {
            if message.isUser {
                closeTurn()
                anchorID = message.id
                userExcerpt = excerpt(message.copyText, limit: userExcerptLimit)
                assistantExcerpt = ""
            } else if message.isAssistant {
                if anchorID == nil { anchorID = message.id }
                if assistantExcerpt.isEmpty {
                    assistantExcerpt = excerpt(message.copyText, limit: assistantExcerptLimit)
                }
            } else if anchorID == nil {
                // Leading system/tool rows belong to no turn yet.
                continue
            }
            turnIndexByMessageID[message.id] = turns.count
        }
        closeTurn()

        return TurnList(turns: turns, turnIndexByMessageID: turnIndexByMessageID)
    }

    // MARK: - Excerpts

    /// Single-line preview of a message for the hover card: whitespace runs
    /// collapse to one space, the result is cut at `limit` characters, and an
    /// ellipsis is appended only when real content was actually dropped
    /// (trailing whitespace alone must not produce a misleading "…").
    ///
    /// Reads at most `limit` characters of the source plus any trailing
    /// whitespace run, so it stays cheap on very long assistant replies.
    static func excerpt(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }

        var result = ""
        result.reserveCapacity(limit + 1)
        var count = 0
        var lastWasSpace = false
        var iterator = text.makeIterator()
        var stoppedOn: Character?

        while let character = iterator.next() {
            if character.isWhitespace {
                // Drop leading whitespace, collapse interior runs.
                if count == 0 || lastWasSpace { continue }
                if count == limit {
                    stoppedOn = character
                    break
                }
                result.append(" ")
                count += 1
                lastWasSpace = true
                continue
            }
            if count == limit {
                stoppedOn = character
                break
            }
            result.append(character)
            count += 1
            lastWasSpace = false
        }

        if lastWasSpace {
            result.removeLast()
        }

        guard let stoppedOn else { return result }
        if !stoppedOn.isWhitespace { return result + ellipsis }
        // We stopped on whitespace — only ellipsize if something non-blank follows.
        while let next = iterator.next() {
            if !next.isWhitespace { return result + ellipsis }
        }
        return result
    }

    // MARK: - Tick layout

    /// Which slice of the turns the rail draws, and whether the ends should
    /// fade to signal there is more in that direction.
    struct Layout: Equatable {
        let visibleRange: Range<Int>
        let fadesTop: Bool
        let fadesBottom: Bool
    }

    /// Ticks keep a fixed `pitch`; when the conversation has more turns than
    /// fit, the rail shows a window centred on the turn you are currently
    /// looking at and slides as you scroll.
    static func layout(
        turnCount: Int,
        activeIndex: Int?,
        availableHeight: CGFloat,
        pitch: CGFloat = tickPitch
    ) -> Layout {
        guard turnCount > 0 else {
            return Layout(visibleRange: 0..<0, fadesTop: false, fadesBottom: false)
        }

        let usablePitch = max(1, pitch)
        let capacity = max(1, Int((max(0, availableHeight) / usablePitch).rounded(.down)))

        guard turnCount > capacity else {
            return Layout(visibleRange: 0..<turnCount, fadesTop: false, fadesBottom: false)
        }

        // No reported position yet means the transcript opened pinned to the
        // bottom, so anchor on the newest turn.
        let anchor = min(max(activeIndex ?? (turnCount - 1), 0), turnCount - 1)
        let start = min(max(anchor - capacity / 2, 0), turnCount - capacity)
        let end = start + capacity

        return Layout(
            visibleRange: start..<end,
            fadesTop: start > 0,
            fadesBottom: end < turnCount
        )
    }

    // MARK: - Render window

    /// Smallest render limit that pulls `messageIndex` into the transcript's
    /// window, which is `messages.suffix(renderLimit)`
    /// (`ChatMessageStagePresentationSupport.TimelineWindow`). Never shrinks an
    /// already-larger limit — collapsing the window under the user would throw
    /// away rows they can currently see.
    static func renderLimit(toInclude messageIndex: Int, totalCount: Int, currentLimit: Int) -> Int {
        guard totalCount > 0 else { return currentLimit }
        let clamped = min(max(messageIndex, 0), totalCount - 1)
        return min(totalCount, max(currentLimit, totalCount - clamped))
    }
}
