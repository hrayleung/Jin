import Foundation

/// Process-wide warm-start cache of measured row heights, keyed strongly
/// enough that a stale hit is effectively impossible: conversation, row
/// identity, wrap-width bucket, a cheap content signature, and a font
/// environment token. The timeline controller's local `heightCache` remains
/// the table's source of truth — this store only pre-seeds it when a
/// conversation is (re)opened, so revisited conversations open with real
/// geometry instead of estimates (the previous behavior re-estimated every
/// row on every open: `apply()` clears the local cache on conversation
/// change).
///
/// In-memory only, deliberately: a height persisted to disk can go stale
/// against font/OS/app-version changes, and a stale height reproduces
/// exactly the scroll jump this exists to eliminate.
@MainActor
final class ChatTimelineRowHeightStore {
    static let shared = ChatTimelineRowHeightStore()

    struct Key: Hashable {
        let conversationID: UUID
        let rowIdentity: String
        let widthBucket: Int
        let contentSignature: UInt64
        let environmentToken: UInt64
    }

    private var heights: [Key: CGFloat] = [:]
    private var insertionOrder: [Key] = []
    private let capacity = 8_000

    func lookup(_ key: Key) -> CGFloat? {
        heights[key]
    }

    func store(_ height: CGFloat, for key: Key) {
        if heights[key] == nil {
            insertionOrder.append(key)
            if insertionOrder.count > capacity {
                let evicted = insertionOrder.removeFirst()
                heights[evicted] = nil
            }
        }
        heights[key] = height
    }

    // MARK: - Key ingredients

    /// O(1)-ish content signature: length + first/last 128 UTF-8 bytes.
    /// Catches edits/regenerations without hashing megabytes; identity +
    /// length collisions with identical 256 boundary bytes are vanishingly
    /// rare, and a visible row re-measures within a frame anyway.
    static func contentSignature(for text: String) -> UInt64 {
        var hasher = FNVHasher()
        hasher.combine(String(text.utf8.count))
        let utf8 = text.utf8
        if utf8.count <= 256 {
            hasher.combine(text)
        } else {
            hasher.combine(String(decoding: utf8.prefix(128), as: UTF8.self))
            hasher.combine(String(decoding: utf8.suffix(128), as: UTF8.self))
        }
        return hasher.value
    }

    /// Font environment: heights are invalid across font-family changes.
    static func environmentToken() -> UInt64 {
        let defaults = UserDefaults.standard
        var hasher = FNVHasher()
        hasher.combine(defaults.string(forKey: AppPreferenceKeys.appFontFamily) ?? "")
        hasher.combine(defaults.string(forKey: AppPreferenceKeys.codeFontFamily) ?? "")
        return hasher.value
    }
}
