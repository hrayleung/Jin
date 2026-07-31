import CoreGraphics
import Foundation
import ImageIO
import os

/// Header-only pixel-size reads (no decode) with a small cache.
///
/// Token estimators consult image dimensions on every send and on
/// context-gauge refreshes; reading the header each time would repeat disk
/// I/O per image per refresh. Attachment files are content-addressed
/// (SHA-named) and never mutated in place, so caching by path is safe.
enum ImagePixelDimensionsCache {
    private struct Storage {
        // `nil` results are cached too, so a corrupt or non-image file does
        // not retrigger I/O on every estimate.
        var dimensionsByPath: [String: CGSize?] = [:]
        var insertionOrder: [String] = []
    }

    private static let capacity = 512
    private static let storage = OSAllocatedUnfairLock(initialState: Storage())

    static func dimensions(for image: ImageContent) -> CGSize? {
        if let url = image.url, url.isFileURL {
            return dimensions(atFileURL: url)
        }
        if let data = image.data {
            // Inline bytes are already resident; the header read is a cheap
            // in-memory parse, so no cache is needed.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return dimensions(from: source)
        }
        return nil
    }

    private static func dimensions(atFileURL url: URL) -> CGSize? {
        let path = url.standardizedFileURL.path
        if let cached = storage.withLock({ $0.dimensionsByPath[path] }) {
            return cached
        }

        let result: CGSize?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            result = dimensions(from: source)
        } else {
            result = nil
        }

        storage.withLock { state in
            if state.dimensionsByPath[path] == nil {
                state.dimensionsByPath[path] = result
                state.insertionOrder.append(path)
                if state.insertionOrder.count > capacity {
                    let evicted = state.insertionOrder.removeFirst()
                    state.dimensionsByPath.removeValue(forKey: evicted)
                }
            }
        }
        return result
    }

    private static func dimensions(from source: CGImageSource) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}
