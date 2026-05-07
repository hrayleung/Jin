import Foundation

enum MessageImageCacheKeySupport {
    static func inlineDataFingerprint(_ data: Data) -> String {
        SHA256HexDigest.dataPrefix(data, byteCount: 8)
    }
}
