import XCTest
@testable import Jin

final class NativeMarkdownParseSchedulingTests: XCTestCase {
    func testStableBrokerCoalescesConcurrentRequestsForSameDocument() async {
        let probe = StableParseProbe()
        let broker = NativeMarkdownStableParseBroker { key, _ in
            await probe.compute(key: key)
        }
        let key = makeKey("stable-single-flight-\(UUID().uuidString)", streaming: false)
        let theme = await MainActor.run {
            MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        }

        let values = await withTaskGroup(
            of: NativeMarkdownCache.Value.self,
            returning: [NativeMarkdownCache.Value].self
        ) { group in
            for _ in 0..<24 {
                group.addTask {
                    await broker.value(for: key, theme: theme, priority: .userInitiated)
                }
            }
            var values: [NativeMarkdownCache.Value] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(values.count, 24)
        let callCount = await probe.callCount()
        let activeRequestCount = await broker.activeRequestCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(activeRequestCount, 0)
        XCTAssertNotNil(NativeMarkdownCache.tryGet(key: key))
    }

    @MainActor
    func testStreamingCoordinatorRunsOneParseAndDropsObsoletePendingPrefixes() async {
        let probe = StreamingParseProbe()
        let coordinator = NativeMarkdownRenderCoordinator { key, _, _ in
            await probe.parse(key: key)
        }
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        let keys = (1...4).map { makeKey(String(repeating: "x", count: $0), streaming: true) }

        coordinator.request(key: keys[0], theme: theme)
        for _ in 0..<100 {
            if await probe.startedCount() > 0 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let initiallyStartedCount = await probe.startedCount()
        XCTAssertEqual(initiallyStartedCount, 1)

        // These arrive in the same main-actor turn while the first synchronous
        // parser is busy. Only the latest prefix should remain queued.
        coordinator.request(key: keys[1], theme: theme)
        coordinator.request(key: keys[2], theme: theme)
        coordinator.request(key: keys[3], theme: theme)

        for _ in 0..<200 {
            if coordinator.output?.key == keys[3] { break }
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertEqual(coordinator.output?.key, keys[3])
        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.startedTexts, [keys[0].markdownText, keys[3].markdownText])
        XCTAssertEqual(snapshot.maximumActiveCount, 1)
    }

    private func makeKey(_ text: String, streaming: Bool) -> NativeMarkdownCache.Key {
        NativeMarkdownCache.Key(
            markdownText: text,
            isStreaming: streaming,
            renderPlainText: false,
            appFontFamily: "",
            codeFontFamily: ""
        )
    }
}

private actor StableParseProbe {
    private var calls = 0

    func compute(key: NativeMarkdownCache.Key) async -> NativeMarkdownCache.Value {
        calls += 1
        try? await Task.sleep(for: .milliseconds(40))
        return emptyMarkdownValue()
    }

    func callCount() -> Int { calls }
}

private actor StreamingParseProbe {
    struct Snapshot {
        let startedTexts: [String]
        let maximumActiveCount: Int
    }

    private var startedTexts: [String] = []
    private var activeCount = 0
    private var maximumActiveCount = 0

    func parse(key: NativeMarkdownCache.Key) async -> NativeMarkdownCache.Value? {
        startedTexts.append(key.markdownText)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        try? await Task.sleep(for: .milliseconds(40))
        activeCount -= 1
        return emptyMarkdownValue()
    }

    func startedCount() -> Int { startedTexts.count }

    func snapshot() -> Snapshot {
        Snapshot(
            startedTexts: startedTexts,
            maximumActiveCount: maximumActiveCount
        )
    }
}

private func emptyMarkdownValue() -> NativeMarkdownCache.Value {
    NativeMarkdownCache.Value(
        blocks: [],
        groups: [],
        layout: NativeAnchorLayoutBuilder.build(groups: [])
    )
}
