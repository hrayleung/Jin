import AppKit

/// A thread-safe NSCache wrapper for NSImage values, keyed by NSString.
final class LockedNSImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private let cache: NSCache<NSString, NSImage>

    init(countLimit: Int) {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = countLimit
        cache = c
    }

    func object(forKey key: NSString) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key)
    }

    func setObject(_ image: NSImage, forKey key: NSString) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key)
    }
}
