import XCTest
@testable import Jin

/// Repro harness for the 2026-06-12 "chat stuck after code output" report:
/// timeline rows measured 128-499px when their true height was 1000-2300px.
/// One candidate mechanism is `NativeMarkdownParseService` running
/// `NativeMarkdownCache.compute` from several detached tasks at once
/// (conversation open realizes multiple rows together) — if anything in the
/// parse pipeline shares mutable state, concurrent parses could yield
/// empty/truncated group lists that the LRU then caches.
final class NativeMarkdownConcurrentParseDeterminismTests: XCTestCase {

    private func fixtureTexts() -> [String] {
        // Mirrors the shape of the affected production messages (prose +
        // fenced code in several languages + inline code + lists + math).
        let zig = """
        In Zig, we pass the function using a function pointer (`*const fn`).

        ```zig
        const std = @import("std");
        fn f(t: f64, y: f64) f64 { return t - y; }
        fn rk4_step(func: *const fn (f64, f64) f64, t: f64, y: f64, h: f64) f64 {
            const k1 = func(t, y);
            const k2 = func(t + h / 2.0, y + h * k1 / 2.0);
            const k3 = func(t + h / 2.0, y + h * k2 / 2.0);
            const k4 = func(t + h, y + h * k3);
            return y + (h / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4);
        }
        ```

        **Output for all programs:**

        ```text
        y(0.1) = 0.909675
        ```
        """
        let python = """
        # Runge-Kutta in Python

        The classic fourth-order method:

        $$k_1 = f(t_n, y_n)$$

        ```python
        def rk4_step(f, t, y, h):
            k1 = f(t, y)
            k2 = f(t + h / 2, y + h * k1 / 2)
            k3 = f(t + h / 2, y + h * k2 / 2)
            k4 = f(t + h, y + h * k3)
            return y + (h / 6) * (k1 + 2 * k2 + 2 * k3 + k4)
        ```

        1. Define the derivative
        2. Step with `rk4_step`
        3. Print the result

        | t | y |
        |---|---|
        | 0.0 | 1.0 |
        | 0.1 | 0.909675 |
        """
        let lorenz = """
        Here's a **Lorenz attractor** 3D plot:

        ```javascript
        const sigma = 10, rho = 28, beta = 8 / 3;
        function step(p, dt) {
            const dx = sigma * (p.y - p.x);
            const dy = p.x * (rho - p.z) - p.y;
            const dz = p.x * p.y - beta * p.z;
            return { x: p.x + dx * dt, y: p.y + dy * dt, z: p.z + dz * dt };
        }
        ```

        > The attractor is chaotic: tiny changes in the initial conditions
        > diverge exponentially.

        - sigma controls the Prandtl number
        - rho is the Rayleigh ratio
        """
        return [zig, python, lorenz]
    }

    private func key(for text: String) -> NativeMarkdownCache.Key {
        NativeMarkdownCache.Key(
            markdownText: text,
            isStreaming: false,
            renderPlainText: false,
            appFontFamily: JinTypography.systemFontPreferenceValue,
            codeFontFamily: JinTypography.systemFontPreferenceValue
        )
    }

    func testConcurrentComputeMatchesSerialCompute() async {
        let texts = fixtureTexts()
        let theme = MarkdownTheme.resolved(
            appFontFamily: JinTypography.systemFontPreferenceValue,
            codeFontFamily: JinTypography.systemFontPreferenceValue
        )

        // Ground truth: serial compute.
        var expected: [Int: (blocks: Int, groups: Int)] = [:]
        for (idx, text) in texts.enumerated() {
            let value = NativeMarkdownCache.compute(key: key(for: text), theme: theme)
            expected[idx] = (value.blocks.count, value.groups.count)
            XCTAssertGreaterThan(value.groups.count, 1, "fixture \(idx) should produce several groups")
        }

        // Hammer: 8 concurrent computes per text, 25 rounds.
        for round in 0..<25 {
            let results = await withTaskGroup(
                of: (Int, Int, Int).self,
                returning: [(Int, Int, Int)].self
            ) { group in
                for (idx, text) in texts.enumerated() {
                    for _ in 0..<8 {
                        group.addTask { [key = key(for: text)] in
                            let value = NativeMarkdownCache.compute(key: key, theme: theme)
                            return (idx, value.blocks.count, value.groups.count)
                        }
                    }
                }
                var collected: [(Int, Int, Int)] = []
                for await item in group { collected.append(item) }
                return collected
            }

            for (idx, blocks, groups) in results {
                XCTAssertEqual(
                    blocks, expected[idx]?.blocks,
                    "round \(round): concurrent parse of fixture \(idx) produced \(blocks) blocks, serial produced \(expected[idx]!.blocks)"
                )
                XCTAssertEqual(
                    groups, expected[idx]?.groups,
                    "round \(round): concurrent parse of fixture \(idx) produced \(groups) groups, serial produced \(expected[idx]!.groups)"
                )
            }
        }
    }
}
