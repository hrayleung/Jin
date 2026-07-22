import Combine
import Foundation

/// Single-flight broker for stable (non-streaming) documents. Conversation
/// prewarming and a newly-realized row frequently ask for the same final text
/// at the same time; only the first request performs the work and every other
/// caller awaits that result.
actor NativeMarkdownStableParseBroker {
    typealias Compute = @Sendable (
        NativeMarkdownCache.Key,
        MarkdownTheme
    ) async -> NativeMarkdownCache.Value

    static let shared = NativeMarkdownStableParseBroker()

    private struct InFlight {
        let token: UInt64
        let task: Task<NativeMarkdownCache.Value, Never>
    }

    private var inFlight: [NativeMarkdownCache.Key: InFlight] = [:]
    private var nextToken: UInt64 = 0
    private let compute: Compute

    init(compute: @escaping Compute = { key, theme in
        NativeMarkdownCache.compute(key: key, theme: theme)
    }) {
        self.compute = compute
    }

    func value(
        for key: NativeMarkdownCache.Key,
        theme: MarkdownTheme,
        priority: TaskPriority
    ) async -> NativeMarkdownCache.Value {
        if let cached = NativeMarkdownCache.tryGet(key: key) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.task.value
        }

        nextToken &+= 1
        let token = nextToken
        let compute = compute
        let task = Task.detached(priority: priority) {
            await compute(key, theme)
        }
        inFlight[key] = InFlight(token: token, task: task)

        let value = await task.value
        if inFlight[key]?.token == token {
            inFlight[key] = nil
        }
        NativeMarkdownCache.insert(value, forKey: key)
        return value
    }

    /// Test/diagnostic visibility without exposing the task objects.
    func activeRequestCount() -> Int {
        inFlight.count
    }
}

/// Background parse entry point. Stable documents use the single-flight
/// broker. Streaming documents are intentionally uncached; their per-view
/// coordinator below guarantees at most one active parse plus one latest
/// pending request.
enum NativeMarkdownParseService {
    static func parse(
        key: NativeMarkdownCache.Key,
        theme: MarkdownTheme,
        priority: TaskPriority = .userInitiated
    ) async -> NativeMarkdownCache.Value? {
        if let cached = NativeMarkdownCache.tryGet(key: key) {
            return cached
        }

        if !key.isStreaming {
            return await NativeMarkdownStableParseBroker.shared.value(
                for: key,
                theme: theme,
                priority: priority
            )
        }

        let task = Task.detached(priority: priority) {
            guard !Task.isCancelled else { return Optional<NativeMarkdownCache.Value>.none }
            return NativeMarkdownCache.compute(key: key, theme: theme)
        }
        let value = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled else { return nil }
        return value
    }
}

/// Owns parse work independently of SwiftUI's short-lived `.task(id:)`
/// lifecycle. Streaming updates replace a single pending request rather than
/// launching another full-document parse while the previous one is still
/// running. Stable requests start immediately and are banked by the global
/// single-flight broker even if a table cell is recycled.
@MainActor
final class NativeMarkdownRenderCoordinator: ObservableObject {
    struct Output {
        let key: NativeMarkdownCache.Key
        let value: NativeMarkdownCache.Value
    }

    typealias Parser = @Sendable (
        NativeMarkdownCache.Key,
        MarkdownTheme,
        TaskPriority
    ) async -> NativeMarkdownCache.Value?

    @Published private(set) var output: Output?

    private struct Request {
        let key: NativeMarkdownCache.Key
        let theme: MarkdownTheme
    }

    private let parser: Parser
    private var latestKey: NativeMarkdownCache.Key?
    private var pendingStreamingRequest: Request?
    private var activeStreamingKey: NativeMarkdownCache.Key?
    private var streamingTask: Task<Void, Never>?
    private var streamingWorkerToken: UInt64 = 0
    private var stableTask: Task<Void, Never>?
    private var stableRequestedKey: NativeMarkdownCache.Key?
    private var stableRequestToken: UInt64 = 0

    init(parser: @escaping Parser = { key, theme, priority in
        await NativeMarkdownParseService.parse(
            key: key,
            theme: theme,
            priority: priority
        )
    }) {
        self.parser = parser
    }

    func request(key: NativeMarkdownCache.Key, theme: MarkdownTheme) {
        latestKey = key

        if let cached = NativeMarkdownCache.tryGet(key: key) {
            cancelStreamingWork()
            cancelStableWork()
            adopt(cached, for: key)
            return
        }

        if key.isStreaming {
            requestStreaming(key: key, theme: theme)
        } else {
            requestStable(key: key, theme: theme)
        }
    }

    func adopt(_ value: NativeMarkdownCache.Value, for key: NativeMarkdownCache.Key) {
        guard output?.key != key else { return }
        output = Output(key: key, value: value)
    }

    private func requestStable(key: NativeMarkdownCache.Key, theme: MarkdownTheme) {
        let streamingTaskToDrain = cancelStreamingWork()

        guard stableRequestedKey != key else { return }
        cancelStableWork()
        stableRequestedKey = key
        let requestToken = stableRequestToken
        let parser = parser
        stableTask = Task { [weak self] in
            // Cancellation cannot interrupt swift-markdown once its
            // synchronous C parse has begun. Drain that obsolete streaming
            // parse before starting the final stable parse so the transition
            // never doubles CPU/memory pressure for the same message.
            await streamingTaskToDrain?.value
            guard let self,
                  !Task.isCancelled,
                  self.stableRequestToken == requestToken else { return }
            let value = await parser(key, theme, .userInitiated)
            if self.stableRequestToken == requestToken {
                self.stableRequestedKey = nil
                self.stableTask = nil
            }
            guard !Task.isCancelled,
                  self.stableRequestToken == requestToken,
                  self.latestKey == key,
                  let value else { return }
            self.adopt(value, for: key)
        }
    }

    private func requestStreaming(key: NativeMarkdownCache.Key, theme: MarkdownTheme) {
        cancelStableWork()

        if activeStreamingKey == key || pendingStreamingRequest?.key == key {
            return
        }
        // Latest wins: replace an obsolete queued prefix. The active parse is
        // allowed to finish because swift-markdown's C parser is synchronous,
        // but no second parse overlaps it for this view.
        pendingStreamingRequest = Request(key: key, theme: theme)
        startStreamingWorkerIfNeeded()
    }

    private func startStreamingWorkerIfNeeded() {
        guard streamingTask == nil else { return }
        streamingWorkerToken &+= 1
        let workerToken = streamingWorkerToken
        let parser = parser
        streamingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let request = self.takePendingStreamingRequest() {
                self.activeStreamingKey = request.key
                let value = await parser(request.key, request.theme, .userInitiated)
                guard self.streamingWorkerToken == workerToken else { return }
                self.activeStreamingKey = nil

                guard !Task.isCancelled else { break }
                if self.latestKey == request.key, let value {
                    self.adopt(value, for: request.key)
                }
            }
            guard self.streamingWorkerToken == workerToken else { return }
            self.streamingTask = nil
            self.activeStreamingKey = nil
            if self.pendingStreamingRequest != nil {
                self.startStreamingWorkerIfNeeded()
            }
        }
    }

    private func takePendingStreamingRequest() -> Request? {
        defer { pendingStreamingRequest = nil }
        return pendingStreamingRequest
    }

    @discardableResult
    private func cancelStreamingWork() -> Task<Void, Never>? {
        let taskToDrain = streamingTask
        streamingWorkerToken &+= 1
        pendingStreamingRequest = nil
        streamingTask?.cancel()
        streamingTask = nil
        activeStreamingKey = nil
        return taskToDrain
    }

    private func cancelStableWork() {
        stableRequestToken &+= 1
        stableTask?.cancel()
        stableTask = nil
        stableRequestedKey = nil
    }

    deinit {
        streamingTask?.cancel()
        stableTask?.cancel()
    }
}
