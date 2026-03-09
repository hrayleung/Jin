import Foundation
import AppKit
import Kingfisher

final class FaviconFailureCache {
    private var failedHosts: [String: Date] = [:]
    let ttl: TimeInterval

    init(ttl: TimeInterval = 15 * 60) {
        self.ttl = ttl
    }

    func isHostFailed(_ normalizedHost: String) -> Bool {
        guard let failedAt = failedHosts[normalizedHost] else { return false }
        if Date().timeIntervalSince(failedAt) > ttl {
            failedHosts[normalizedHost] = nil
            return false
        }
        return true
    }

    func recordFailure(for normalizedHost: String) {
        failedHosts[normalizedHost] = Date()
    }
}

actor FaviconLoader {
    static let shared = FaviconLoader()

    typealias ImageRetriever = @Sendable (FaviconSourceResolver.ResolvedSources) async throws -> NSImage

    private enum RetrievalOutcome {
        case success(NSImage)
        case failure
        case cancelled
    }

    private let failureCache: FaviconFailureCache
    private let imageRetriever: ImageRetriever
    private var inFlightByHost: [String: Task<RetrievalOutcome, Never>] = [:]

    init(
        failureCache: FaviconFailureCache = FaviconFailureCache(),
        imageRetriever: ImageRetriever? = nil
    ) {
        self.failureCache = failureCache
        self.imageRetriever = imageRetriever ?? { resolved in
            try await Self.retrieveImageWithKingfisher(resolved: resolved)
        }
    }

    func favicon(for rawHost: String) async -> NSImage? {
        guard let resolved = FaviconSourceResolver.sources(for: rawHost) else { return nil }

        let host = resolved.normalizedHost

        if failureCache.isHostFailed(host) { return nil }

        if let inFlight = inFlightByHost[host] {
            return image(from: await inFlight.value, for: host)
        }

        let retrieveImage = self.imageRetriever
        let task = Task<RetrievalOutcome, Never> {
            do {
                return .success(try await retrieveImage(resolved))
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure
            }
        }
        inFlightByHost[host] = task
        let outcome = await task.value
        inFlightByHost[host] = nil

        return image(from: outcome, for: host)
    }

    static func retrieveImageWithKingfisher(
        resolved: FaviconSourceResolver.ResolvedSources,
        manager: KingfisherManager = .shared,
        cache: ImageCache = .default,
        downloader: ImageDownloader = FaviconSourceResolver.imageDownloader
    ) async throws -> NSImage {
        let result = try await manager.retrieveImage(
            with: resolved.primary,
            options: FaviconSourceResolver.options(
                for: resolved,
                cache: cache,
                downloader: downloader
            )
        )
        return result.image
    }

    private func image(from outcome: RetrievalOutcome, for host: String) -> NSImage? {
        switch outcome {
        case .success(let image):
            return image
        case .failure:
            failureCache.recordFailure(for: host)
            return nil
        case .cancelled:
            return nil
        }
    }
}
