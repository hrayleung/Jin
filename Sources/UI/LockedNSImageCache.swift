import AppKit

/// A thread-safe NSCache wrapper for NSImage values, keyed by NSString.
final class LockedNSImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private let cache: NSCache<NSString, NSImage>

    /// `totalCostLimit` bounds decoded-bitmap bytes (pass the bitmap size as
    /// the cost on `setObject`); a count limit alone lets a few hundred
    /// full-resolution images grow into the GB range. 0 = unbounded.
    init(countLimit: Int, totalCostLimit: Int = 0) {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = countLimit
        c.totalCostLimit = totalCostLimit
        cache = c
    }

    func object(forKey key: NSString) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key)
    }

    func setObject(_ image: NSImage, forKey key: NSString, cost: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key, cost: cost)
    }
}
