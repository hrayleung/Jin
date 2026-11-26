import AppKit
import QuartzCore
import XCTest
@testable import Jin

final class JinActivityOrbEngineTests: XCTestCase {
    func testInlineAndHeroSizesArePurposeTuned() {
        XCTAssertEqual(JinActivityOrbSize.inline.rawValue, 20)
        XCTAssertEqual(JinActivityOrbSize.hero.rawValue, 64)
    }

    func testStreamingPlaceholderMinHeightIsUnchanged() {
        XCTAssertEqual(JinStreamingPlaceholder.preferredMinHeight, 28)
    }

    func testModeMappingUsesTheFourShippedVerbs() {
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .working), .orbits)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .searching), .globe)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .listening), .wave)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .thinking), .ring)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .composing), .ring)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .solving), .rubik)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .connecting), .orbits)
        XCTAssertEqual(JinActivityOrbEngine.mode(for: .shaping), .orbits)
    }

    func testInlineFramesStayInsideTheTwentyPointBox() {
        for kind in JinActivityKind.allCases {
            let frame = JinActivityOrbEngine.frame(
                kind: kind,
                size: .inline,
                t: JinActivityOrbEngine.reducedMotionT
            )
            XCTAssertFalse(frame.dots.isEmpty, "\(kind.rawValue) should emit dots")
            for dot in frame.dots {
                XCTAssertGreaterThan(dot.x, -4, "\(kind.rawValue) x=\(dot.x)")
                XCTAssertLessThan(dot.x, 24, "\(kind.rawValue) x=\(dot.x)")
                XCTAssertGreaterThan(dot.y, -4, "\(kind.rawValue) y=\(dot.y)")
                XCTAssertLessThan(dot.y, 24, "\(kind.rawValue) y=\(dot.y)")
            }
        }
    }

    func testReducedMotionInstantIsDeterministic() {
        let first = JinActivityOrbEngine.frame(kind: .working, size: .inline, t: 0.6)
        let second = JinActivityOrbEngine.frame(kind: .working, size: .inline, t: 0.6)
        XCTAssertEqual(first.dots.count, second.dots.count)
        for (lhs, rhs) in zip(first.dots, second.dots) {
            XCTAssertEqual(lhs.x, rhs.x, accuracy: 1e-9)
            XCTAssertEqual(lhs.y, rhs.y, accuracy: 1e-9)
            XCTAssertEqual(lhs.r, rhs.r, accuracy: 1e-9)
            XCTAssertEqual(lhs.a, rhs.a, accuracy: 1e-9)
        }
    }

    func testReducedMotionConstantMatchesEngineInstant() {
        XCTAssertEqual(JinActivityOrbEngine.reducedMotionT, 0.6)
    }

    func testPrewarmInlinePresetsIsIdempotent() {
        JinActivityOrbEngine.prewarmInlinePresets()
        JinActivityOrbEngine.prewarmInlinePresets()
        let frame = JinActivityOrbEngine.frame(
            kind: .working,
            size: .inline,
            t: JinActivityOrbEngine.reducedMotionT
        )
        XCTAssertFalse(frame.dots.isEmpty)
    }

    func testAnimationPlansKeepStableDotsAndCloseTheirLoop() {
        for kind in JinActivityKind.allCases {
            let plan = JinActivityOrbEngine.animationPlan(kind: kind, size: .inline)
            let first = try! XCTUnwrap(plan.frames.first)
            let last = try! XCTUnwrap(plan.frames.last)

            XCTAssertGreaterThan(plan.frames.count, 2)
            XCTAssertGreaterThan(plan.dotCount, 0)
            XCTAssertTrue(plan.frames.allSatisfy { $0.dots.count == plan.dotCount })
            XCTAssertEqual(first.dots.count, last.dots.count)
            for (lhs, rhs) in zip(first.dots, last.dots) {
                XCTAssertEqual(lhs.x, rhs.x, accuracy: 1e-9)
                XCTAssertEqual(lhs.y, rhs.y, accuracy: 1e-9)
                XCTAssertEqual(lhs.r, rhs.r, accuracy: 1e-9)
                XCTAssertEqual(lhs.a, rhs.a, accuracy: 1e-9)
            }
        }
    }

    func testSettledThoughtFrameIsSolvingRestNotARing() {
        let settled = JinActivityOrbEngine.settledThoughtFrame(size: .inline)
        let frozenThinking = JinActivityOrbEngine.frame(
            kind: .thinking,
            size: .inline,
            t: JinActivityOrbEngine.reducedMotionT
        )
        let liveSolvingRest = JinActivityOrbEngine.frame(
            kind: .solving,
            size: .inline,
            t: activityOrbRubikRestInstant(moveCount: 14)
        )

        // A globe lattice, not the 9-dot UFO ring.
        XCTAssertGreaterThan(settled.dots.count, 12)
        XCTAssertLessThanOrEqual(settled.dots.count, JinActivityOrbEngine.inlineDotBudget)
        XCTAssertEqual(settled.dots.count, liveSolvingRest.dots.count)

        let settledFingerprint = settled.dots.flatMap { [$0.x, $0.y, $0.r] }
        let thinkingFingerprint = frozenThinking.dots.flatMap { [$0.x, $0.y, $0.r] }
        XCTAssertNotEqual(settledFingerprint, thinkingFingerprint)

        let again = JinActivityOrbEngine.settledThoughtFrame(size: .inline)
        XCTAssertEqual(again.dots.count, settled.dots.count)
        for (lhs, rhs) in zip(settled.dots, again.dots) {
            XCTAssertEqual(lhs.x, rhs.x, accuracy: 1e-9)
            XCTAssertEqual(lhs.y, rhs.y, accuracy: 1e-9)
        }

        for dot in settled.dots {
            XCTAssertGreaterThan(dot.x, -4)
            XCTAssertLessThan(dot.x, 24)
            XCTAssertGreaterThan(dot.y, -4)
            XCTAssertLessThan(dot.y, 24)
        }
    }

    func testInlineFramesStayWithinDotBudget() {
        for kind in JinActivityKind.allCases {
            let frame = JinActivityOrbEngine.frame(
                kind: kind,
                size: .inline,
                t: JinActivityOrbEngine.reducedMotionT
            )
            XCTAssertLessThanOrEqual(
                frame.dots.count,
                JinActivityOrbEngine.inlineDotBudget,
                "\(kind.rawValue) emitted \(frame.dots.count) dots"
            )
        }
    }

    @MainActor
    func testNSViewNormalLiveModeInstallsFullActivityAnimation() {
        let (window, orb) = makeHostedOrbView()
        defer { window.orderOut(nil) }

        orb.apply(
            kind: .working,
            size: .inline,
            paused: false,
            reduceMotion: false,
            pose: .live,
            isDark: true
        )

        let dotLayers = dotSublayers(in: orb)
        XCTAssertFalse(dotLayers.isEmpty)
        for dotLayer in dotLayers {
            XCTAssertEqual(dotLayer.animationKeys(), ["jin.activity"])
            let group = dotLayer.animation(forKey: "jin.activity") as? CAAnimationGroup
            XCTAssertNotNil(group)
            XCTAssertEqual(group?.beginTime, 0)
            XCTAssertEqual(group?.repeatCount, .infinity)
            let keyPaths = Set((group?.animations ?? []).compactMap { ($0 as? CAPropertyAnimation)?.keyPath })
            XCTAssertEqual(keyPaths, ["position", "transform.scale", "opacity"])
        }
    }

    @MainActor
    func testNSViewReducedMotionLiveModeInstallsOpacityOnlyBreathing() {
        let (window, orb) = makeHostedOrbView()
        defer { window.orderOut(nil) }

        for kind in [JinActivityKind.working, .searching] {
            orb.apply(
                kind: kind,
                size: .inline,
                paused: false,
                reduceMotion: true,
                pose: .live,
                isDark: true
            )

            let preset = JinActivityOrbEngine.resolve(kind, size: .inline)
            let expectedStatic = JinActivityOrbEngine.frame(
                preset,
                size: JinActivityOrbSize.inline.value,
                t: JinActivityOrbEngine.reducedMotionT * preset.speed
            )
            let dotLayers = dotSublayers(in: orb)
            XCTAssertEqual(dotLayers.count, expectedStatic.dots.count)

            for (dotLayer, expectedDot) in zip(dotLayers, expectedStatic.dots) {
                XCTAssertEqual(dotLayer.position.x, expectedDot.x, accuracy: 1e-6)
                XCTAssertEqual(dotLayer.position.y, expectedDot.y, accuracy: 1e-6)
                XCTAssertEqual(dotLayer.animationKeys(), ["jin.activity.reduceMotion"])
                let pulse = dotLayer.animation(forKey: "jin.activity.reduceMotion") as? CAKeyframeAnimation
                XCTAssertNotNil(pulse)
                XCTAssertEqual(pulse?.keyPath, "opacity")
                XCTAssertEqual(pulse?.beginTime, 0)
                XCTAssertEqual(pulse?.repeatCount, .infinity)
                XCTAssertGreaterThan(pulse?.duration ?? 0, 0)
            }
        }
    }

    @MainActor
    func testNSViewPausedAndSettledModesInstallNoAnimations() {
        let (window, orb) = makeHostedOrbView()
        defer { window.orderOut(nil) }

        let cases: [(Bool, Bool, JinActivityOrbPose)] = [
            (true, false, .live),
            (true, true, .live),
            (false, false, .settled),
            (false, true, .settled),
        ]

        for (paused, reduceMotion, pose) in cases {
            orb.apply(
                kind: .working,
                size: .inline,
                paused: paused,
                reduceMotion: reduceMotion,
                pose: pose,
                isDark: true
            )

            let dotLayers = dotSublayers(in: orb)
            XCTAssertFalse(dotLayers.isEmpty)
            for dotLayer in dotLayers {
                XCTAssertTrue(
                    (dotLayer.animationKeys() ?? []).isEmpty,
                    "Expected static dot layer for paused=\(paused) reduceMotion=\(reduceMotion) pose=\(pose)"
                )
            }
        }
    }

    @MainActor
    func testNSViewTransitionsCleanlyAcrossMotionModes() {
        let (window, orb) = makeHostedOrbView()
        defer { window.orderOut(nil) }

        orb.apply(kind: .searching, size: .inline, paused: false, reduceMotion: false, pose: .live, isDark: true)
        XCTAssertTrue(dotSublayers(in: orb).allSatisfy { $0.animationKeys() == ["jin.activity"] })

        orb.apply(kind: .searching, size: .inline, paused: false, reduceMotion: true, pose: .live, isDark: true)
        XCTAssertTrue(dotSublayers(in: orb).allSatisfy { $0.animationKeys() == ["jin.activity.reduceMotion"] })

        orb.apply(kind: .searching, size: .inline, paused: true, reduceMotion: true, pose: .live, isDark: true)
        XCTAssertTrue(dotSublayers(in: orb).allSatisfy { ($0.animationKeys() ?? []).isEmpty })

        orb.apply(kind: .searching, size: .inline, paused: false, reduceMotion: false, pose: .live, isDark: true)
        XCTAssertTrue(dotSublayers(in: orb).allSatisfy { $0.animationKeys() == ["jin.activity"] })
    }

    @MainActor
    private func makeHostedOrbView() -> (NSWindow, JinActivityOrbNSView) {
        let orb = JinActivityOrbNSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(orb)
        window.displayIfNeeded()
        return (window, orb)
    }

    @MainActor
    private func dotSublayers(in orb: JinActivityOrbNSView) -> [CALayer] {
        orb.layer?.sublayers?.first?.sublayers ?? []
    }
}
