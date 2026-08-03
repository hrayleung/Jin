import Foundation

/// Content-keyed memo for `FuzzyMatchField`.
///
/// Keyed by `(text, prominence)`, so there is no invalidation problem: a renamed
/// provider or a re-fetched model is simply a different key. Model names and IDs
/// repeat heavily across providers (`openai/gpt-oss-120b` ships under half a dozen
/// gateways), so the hit rate is high even on the first keystroke.
final class FuzzyMatchFieldCache: @unchecked Sendable {
    static let shared = FuzzyMatchFieldCache()

    private struct Key: Hashable {
        let text: String
        let prominence: Int
    }

    private let lock = NSLock()
    private let capacity: Int
    private var storage: [Key: FuzzyMatchField] = [:]

    /// Jin's entire shipped catalog is on the order of a thousand distinct strings.
    init(capacity: Int = 8192) {
        self.capacity = capacity
    }

    func field(_ text: String, prominence: FuzzyMatchField.Prominence = .primary) -> FuzzyMatchField {
        let key = Key(text: text, prominence: prominence.rawValue)

        lock.lock()
        let cached = storage[key]
        lock.unlock()
        if let cached { return cached }

        let field = FuzzyMatchField(text, prominence: prominence)

        lock.lock()
        if storage.count >= capacity {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = field
        lock.unlock()

        return field
    }

    func removeAll() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
