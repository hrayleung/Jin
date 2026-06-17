import XCTest
@testable import Jin

/// Pins the Fireworks serverless-catalog fallback table (models not in the curated
/// ModelCatalog). These context windows are deliberately distinct (e.g. 196_600 vs
/// 196_608, 202_800 vs 202_752); this guards the keyed-table refactor against any
/// per-entry drift.
final class FireworksFallbackModelInfoTests: XCTestCase {
    private func info(_ canonical: String) -> ModelInfo {
        FireworksAdapter.fireworksFallbackModelInfo(id: "fireworks/\(canonical)", canonical: canonical)
    }

    private func assertModel(
        _ canonical: String,
        name: String,
        window: Int,
        vision: Bool = false,
        audio: Bool = false,
        reasoning: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let m = info(canonical)
        XCTAssertEqual(m.name, name, "\(canonical) name", file: file, line: line)
        XCTAssertEqual(m.contextWindow, window, "\(canonical) window", file: file, line: line)
        XCTAssertEqual(m.capabilities.contains(.vision), vision, "\(canonical) vision", file: file, line: line)
        XCTAssertEqual(m.capabilities.contains(.audio), audio, "\(canonical) audio", file: file, line: line)
        XCTAssertEqual(m.capabilities.contains(.reasoning), reasoning, "\(canonical) reasoning", file: file, line: line)
        XCTAssertEqual(m.reasoningConfig != nil, reasoning, "\(canonical) reasoningConfig", file: file, line: line)
        XCTAssertTrue(m.capabilities.contains(.streaming) && m.capabilities.contains(.toolCalling), "\(canonical) base caps", file: file, line: line)
    }

    func testFallbackTable() {
        assertModel("deepseek-v3p2", name: "DeepSeek V3.2", window: 163_800)
        assertModel("kimi-k2-instruct-0905", name: "Kimi K2 Instruct 0905", window: 262_100)
        assertModel("kimi-k2p6", name: "Kimi K2.6", window: 262_100, vision: true, reasoning: true)
        assertModel("kimi-k2p5", name: "Kimi K2.5", window: 262_100, vision: true, reasoning: true)
        assertModel("qwen3-235b-a22b", name: "Qwen3 235B A22B", window: 131_100)
        assertModel("qwen3-8b", name: "Qwen3 8B", window: 40_960)
        assertModel("qwen3p6-plus", name: "Qwen3.6 Plus", window: 128_000, vision: true)
        assertModel("llama-v3p3-70b-instruct", name: "Llama 3.3 70B Instruct", window: 131_072)
        assertModel("minimax-m2", name: "MiniMax M2", window: 196_600, reasoning: true)
        assertModel("minimax-m2p1", name: "MiniMax M2.1", window: 204_800, reasoning: true)
        assertModel("minimax-m2p5", name: "MiniMax M2.5", window: 196_600, reasoning: true)
        assertModel("minimax-m2p7", name: "MiniMax M2.7", window: 196_608, reasoning: true)
        assertModel("glm-4p7", name: "GLM-4.7", window: 202_800, reasoning: true)
        assertModel("glm-5", name: "GLM-5", window: 202_800, reasoning: true)
        assertModel("glm-5p2", name: "GLM-5.2", window: 202_752, reasoning: true)
        assertModel("glm-5p1", name: "GLM-5.1", window: 202_752, reasoning: true)
        assertModel("qwen3-omni-30b-a3b-instruct", name: "fireworks/qwen3-omni-30b-a3b-instruct", window: 128_000, vision: true, audio: true)
        assertModel("qwen3-asr-4b", name: "fireworks/qwen3-asr-4b", window: 128_000, audio: true)
    }

    func testUnknownModelGetsDefaults() {
        let m = FireworksAdapter.fireworksFallbackModelInfo(id: "fireworks/totally-unknown", canonical: "totally-unknown")
        XCTAssertEqual(m.name, "fireworks/totally-unknown")
        XCTAssertEqual(m.contextWindow, 128_000)
        XCTAssertNil(m.reasoningConfig)
        XCTAssertFalse(m.capabilities.contains(.vision))
        XCTAssertFalse(m.capabilities.contains(.reasoning))
        XCTAssertTrue(m.capabilities.contains(.streaming))
    }

    func testNilCanonicalGetsDefaults() {
        let m = FireworksAdapter.fireworksFallbackModelInfo(id: "weird-id", canonical: nil)
        XCTAssertEqual(m.name, "weird-id")
        XCTAssertEqual(m.contextWindow, 128_000)
        XCTAssertNil(m.reasoningConfig)
    }
}
