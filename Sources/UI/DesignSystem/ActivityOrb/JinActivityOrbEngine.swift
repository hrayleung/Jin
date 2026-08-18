// Curated subset of the thinking-orbs SwiftUI engine (MIT © 2026 Jakub Antalik).
// Transcribed from packages/thinking-orbs/ports/ios/ThinkingOrbsKit.
// https://github.com/Jakubantalik/Libraries
//
// Doubles throughout: the upstream golden vectors come from JavaScript
// numbers (IEEE-754 doubles). Float would drift the trig-heavy modes.

import Foundation

enum JinActivityOrbSize: Int, CaseIterable, Sendable {
    case inline = 20
    case hero = 64

    var value: Double { Double(rawValue) }
}

enum JinActivityOrbMode: String, Sendable {
    case orbits
    case globe
    case rubik
    case wave
    case ring
}

struct ActivityOrbDot: Sendable {
    var x: Double
    var y: Double
    var z: Double
    var r: Double
    var white: Double
    var a: Double
}

struct ActivityOrbLine: Sendable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var white: Double
    var a: Double
    var w: Double
}

struct ActivityOrbFrame: Sendable {
    var dots: [ActivityOrbDot]
    var lines: [ActivityOrbLine]
}

struct ActivityOrbAnimationPlan: Sendable {
    let duration: TimeInterval
    let frames: [ActivityOrbFrame]

    var dotCount: Int {
        frames.first?.dots.count ?? 0
    }
}

enum JinActivityOrbEngine {
    /// Instant used for reduced-motion / paused static frames.
    static let reducedMotionT: Double = 0.6
    /// Core Animation interpolates these samples at the display refresh rate.
    /// The engine only pays this cost once per mode, never once per frame.
    static let animationDuration: TimeInterval = 4.8
    static let animationSampleCount = 120
    private static let animationSeamSampleCount = 20

    /// Resolve and sample every inline mode ahead of the first send.
    static func prewarmInlinePresets() {
        var warmedModes = Set<JinActivityOrbMode>()
        for kind in JinActivityKind.allCases {
            let mode = mode(for: kind)
            guard warmedModes.insert(mode).inserted else { continue }
            _ = animationPlan(mode: mode, size: .inline)
        }
    }

    static func mode(for kind: JinActivityKind) -> JinActivityOrbMode {
        switch kind {
        case .searching:
            return .globe
        case .listening:
            return .wave
        case .thinking, .composing:
            return .ring
        case .solving:
            return .rubik
        case .working, .connecting, .shaping:
            return .orbits
        }
    }

    static func resolve(_ kind: JinActivityKind, size: JinActivityOrbSize) -> ResolvedActivityOrbPreset {
        resolvePreset(mode: mode(for: kind), size: size)
    }

    static func frame(kind: JinActivityKind, size: JinActivityOrbSize, t: Double) -> ActivityOrbFrame {
        let preset = resolve(kind, size: size)
        return frame(preset, size: size.value, t: t)
    }

    static func animationPlan(
        kind: JinActivityKind,
        size: JinActivityOrbSize
    ) -> ActivityOrbAnimationPlan {
        animationPlan(mode: mode(for: kind), size: size)
    }

    private static func animationPlan(
        mode: JinActivityOrbMode,
        size: JinActivityOrbSize
    ) -> ActivityOrbAnimationPlan {
        let key = "\(mode.rawValue)-\(size.rawValue)"
        return activityOrbAnimationPlanCache.resolve(key: key) {
            let preset = resolvePreset(mode: mode, size: size)
            var frames = (0..<animationSampleCount).map { index in
                let phase = Double(index) / Double(animationSampleCount)
                return frame(
                    preset,
                    size: size.value,
                    t: phase * animationDuration * preset.speed
                )
            }

            guard let first = frames.first,
                  frames.allSatisfy({ $0.dots.count == first.dots.count }) else {
                let fallback = frame(
                    preset,
                    size: size.value,
                    t: reducedMotionT * preset.speed
                )
                return ActivityOrbAnimationPlan(
                    duration: animationDuration,
                    frames: [fallback, fallback]
                )
            }

            // The upstream equations use several unrelated frequencies, so
            // they do not share a short natural period. Ease the tail back to
            // frame zero to make the compositor loop continuous.
            let seamStart = max(0, frames.count - animationSeamSampleCount)
            if seamStart < frames.count {
                let seamLength = Double(frames.count - seamStart + 1)
                for index in seamStart..<frames.count {
                    let linear = Double(index - seamStart + 1) / seamLength
                    let eased = linear * linear * (3 - 2 * linear)
                    frames[index] = activityOrbInterpolateFrame(
                        frames[index],
                        first,
                        progress: eased
                    )
                }
            }
            frames.append(first)
            return ActivityOrbAnimationPlan(duration: animationDuration, frames: frames)
        }
    }

    /// `solving` rest — bands have clicked back to the unscrambled lattice.
    ///
    /// thinking-orbs has no "done" verb. `solving` is the only state whose
    /// cycle includes a solved hold (`2 * moveCount * 0.42`, then 1.2s rest).
    /// That hold is the finished-thought pose, not a frozen live frame and
    /// not a face-on ring.
    static func settledThoughtFrame(size: JinActivityOrbSize) -> ActivityOrbFrame {
        let preset = resolve(.solving, size: size)
        let moveCount = preset.opts["moveCount"] ?? 14
        return frame(preset, size: size.value, t: activityOrbRubikRestInstant(moveCount: moveCount))
    }

    /// Inline (20pt) frames stay under this so a chat header never paints a
    /// filled disk. Hero (64pt) keeps the richer counts.
    static let inlineDotBudget = 36

    static func frame(_ preset: ResolvedActivityOrbPreset, size: Double, t: Double) -> ActivityOrbFrame {
        let opts = preset.opts
        let raw: ActivityOrbFrame
        switch preset.mode {
        case .orbits:
            raw = activityOrbFrameOrbits(size, t, opts)
        case .globe:
            raw = activityOrbFrameGlobe(size, t, opts)
        case .rubik:
            raw = activityOrbFrameRubik(size, t, opts)
        case .wave:
            raw = activityOrbFrameWave(size, t, opts)
        case .ring:
            raw = activityOrbFrameRibbon(size, t, opts)
        }
        guard size <= JinActivityOrbSize.inline.value, raw.dots.count > inlineDotBudget else {
            return raw
        }
        return thinned(raw, limit: inlineDotBudget)
    }

    private static func thinned(_ frame: ActivityOrbFrame, limit: Int) -> ActivityOrbFrame {
        guard frame.dots.count > limit, limit > 0 else { return frame }
        let step = Double(frame.dots.count) / Double(limit)
        var dots: [ActivityOrbDot] = []
        dots.reserveCapacity(limit)
        var cursor = 0.0
        while dots.count < limit, Int(cursor) < frame.dots.count {
            dots.append(frame.dots[Int(cursor)])
            cursor += step
        }
        return ActivityOrbFrame(dots: dots, lines: frame.lines)
    }
}

struct ResolvedActivityOrbPreset: Sendable {
    let mode: JinActivityOrbMode
    let speed: Double
    let opts: [String: Double]
}

// MARK: - Shared math (upstream Core.swift)

@inlinable
func activityOrbHashD(_ a: Double, _ b: Double) -> Double {
    let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
    return h - floor(h)
}

@inlinable
func activityOrbFibDir(_ i: Int, _ n: Int) -> (Double, Double, Double) {
    let golden = Double.pi * (3 - (5.0).squareRoot())
    let y = 1 - (2 * (Double(i) + 0.5)) / Double(n)
    let rad = (1 - y * y).squareRoot()
    let a = Double(i) * golden
    return (rad * cos(a), y, rad * sin(a))
}

@inlinable
func activityOrbAngleDelta(_ a: Double, _ b: Double) -> Double {
    atan2(sin(a - b), cos(a - b))
}

@inlinable
func activityOrbRadiusScale(_ size: Double, pow p: Double) -> Double {
    Foundation.pow(size / 300, p)
}

struct ActivityOrbProjector {
    let st: Double, ct: Double, sy: Double, cyw: Double
    let cx: Double, cy: Double, scale: Double

    init(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double) {
        self.st = sin(tilt)
        self.ct = cos(tilt)
        self.sy = sin(yaw)
        self.cyw = cos(yaw)
        self.cx = cx
        self.cy = cy
        self.scale = scale
    }

    @inlinable
    func callAsFunction(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        let x1 = x * cyw + z * sy
        let z1 = -x * sy + z * cyw
        let y1 = y * ct - z1 * st
        let z2 = y * st + z1 * ct
        return (cx + x1 * scale, cy - y1 * scale, z2)
    }
}

func activityOrbFinalizeFrame(
    _ dots: [ActivityOrbDot],
    _ lines: [ActivityOrbLine],
    rMin: Double = 0.3,
    sortByDepth: Bool = true
) -> ActivityOrbFrame {
    var visible: [ActivityOrbDot] = []
    visible.reserveCapacity(dots.count)
    for var dot in dots where dot.a >= 0.02 {
        dot.r = Swift.max(rMin, dot.r)
        visible.append(dot)
    }
    let ordered: [ActivityOrbDot]
    if sortByDepth {
        ordered = visible.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.z != rhs.element.z {
                    return lhs.element.z < rhs.element.z
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    } else {
        ordered = visible
    }
    return ActivityOrbFrame(dots: ordered, lines: lines.filter { $0.a >= 0.02 })
}

private func activityOrbInterpolateFrame(
    _ from: ActivityOrbFrame,
    _ to: ActivityOrbFrame,
    progress: Double
) -> ActivityOrbFrame {
    guard from.dots.count == to.dots.count,
          from.lines.count == to.lines.count else {
        return to
    }
    let t = min(1, max(0, progress))
    let dots = zip(from.dots, to.dots).map { lhs, rhs in
        ActivityOrbDot(
            x: activityOrbLerp(lhs.x, rhs.x, t),
            y: activityOrbLerp(lhs.y, rhs.y, t),
            z: activityOrbLerp(lhs.z, rhs.z, t),
            r: activityOrbLerp(lhs.r, rhs.r, t),
            white: activityOrbLerp(lhs.white, rhs.white, t),
            a: activityOrbLerp(lhs.a, rhs.a, t)
        )
    }
    let lines = zip(from.lines, to.lines).map { lhs, rhs in
        ActivityOrbLine(
            x1: activityOrbLerp(lhs.x1, rhs.x1, t),
            y1: activityOrbLerp(lhs.y1, rhs.y1, t),
            x2: activityOrbLerp(lhs.x2, rhs.x2, t),
            y2: activityOrbLerp(lhs.y2, rhs.y2, t),
            white: activityOrbLerp(lhs.white, rhs.white, t),
            a: activityOrbLerp(lhs.a, rhs.a, t),
            w: activityOrbLerp(lhs.w, rhs.w, t)
        )
    }
    return ActivityOrbFrame(dots: dots, lines: lines)
}

@inline(__always)
private func activityOrbLerp(_ from: Double, _ to: Double, _ progress: Double) -> Double {
    from + (to - from) * progress
}

// MARK: - Spec + presets (20pt / 64pt only)

private enum ActivityOrbSpec {
    static let baseProfiles: [JinActivityOrbMode: [String: Double]] = [
        .orbits: [
            "orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5,
            "particles": 3, "partR": 1.2, "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3
        ],
        .globe: [
            "latRings": 17, "lonDensity": 44, "rBase": 0.6, "rDepth": 1.7, "rBoost": 1,
            "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3
        ],
        .rubik: [
            "latRings": 15, "lonDensity": 40, "moveCount": 14,
            "rBase": 0.6, "rDepth": 1.7, "rActive": 0.3,
            "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3
        ],
        .wave: [
            "rings": 15, "lonDensity": 40, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3
        ],
        .ring: [
            "lanes": 5, "segs": 88, "ghostN": 0, "faceOn": 1, "rBase": 1.1, "rDepth": 1.7,
            "rsPow": 0.6, "rMin": 0.3
        ]
    ]

    struct Preset {
        let speed: Double
        let count: Double
        let size: Double
        let extra: [String: Double]
    }

    static let presets: [JinActivityOrbMode: [JinActivityOrbSize: Preset]] = [
        .orbits: [
            .hero: Preset(speed: 1.885, count: 1, size: 1, extra: [:]),
            .inline: Preset(speed: 3.9, count: 0.238, size: 2.4, extra: [:])
        ],
        .globe: [
            .hero: Preset(speed: 2.015, count: 0.42, size: 1.15, extra: ["scanMul": 4.08, "dimBase": 0.45]),
            .inline: Preset(speed: 2.665, count: 0.05, size: 1.75, extra: ["scanMul": 4.335, "dimBase": 0.45])
        ],
        .rubik: [
            .hero: Preset(speed: 1.82, count: 0.35, size: 1.05, extra: [:]),
            .inline: Preset(speed: 1.95, count: 0.088, size: 1.9, extra: [:])
        ],
        .wave: [
            .hero: Preset(speed: 4.388, count: 0.341, size: 1, extra: [:]),
            .inline: Preset(speed: 3.998, count: 0.05, size: 1.6, extra: [:])
        ],
        .ring: [
            .hero: Preset(speed: 3.24, count: 0.25, size: 0.956, extra: ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]),
            .inline: Preset(speed: 3.78, count: 0.028, size: 1.622, extra: ["spin": 0, "bandMul": 1, "wobMul": 0.565])
        ]
    ]

    static let countPairs: [(String, String)] = [
        ("latRings", "lonDensity"),
        ("rings", "lonDensity"),
        ("lanes", "segs")
    ]
    static let countKeys: [String] = ["orbitN", "ghostN", "particles"]
    static let radiusKeys: [String] = ["rBase", "rDepth", "rActive", "ghostR", "partR", "partRDepth"]
}

private func scaleActivityOrbCounts(_ opts: [String: Double], _ scale: Double) -> [String: Double] {
    var out = opts
    var done = Set<String>()
    let rt = scale.squareRoot()
    for (a, b) in ActivityOrbSpec.countPairs {
        if let va = out[a], let vb = out[b], !done.contains(a), !done.contains(b) {
            out[a] = Swift.max(2, (va * rt).rounded(.toNearestOrAwayFromZero))
            out[b] = Swift.max(2, (vb * rt).rounded(.toNearestOrAwayFromZero))
            done.insert(a)
            done.insert(b)
        }
    }
    for key in ActivityOrbSpec.countKeys {
        if let value = out[key], value != 0, !done.contains(key) {
            out[key] = Swift.max(1, (value * scale).rounded(.toNearestOrAwayFromZero))
        }
    }
    return out
}

private func scaleActivityOrbRadii(_ opts: [String: Double], _ scale: Double) -> [String: Double] {
    var out = opts
    for key in ActivityOrbSpec.radiusKeys {
        if let value = out[key] {
            out[key] = value * scale
        }
    }
    return out
}

private final class ActivityOrbPresetCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: ResolvedActivityOrbPreset] = [:]

    func resolve(
        key: String,
        make: () -> ResolvedActivityOrbPreset
    ) -> ResolvedActivityOrbPreset {
        lock.lock()
        if let hit = storage[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let resolved = make()
        lock.lock()
        defer { lock.unlock() }
        if let racedHit = storage[key] {
            return racedHit
        }
        storage[key] = resolved
        return resolved
    }
}

private final class ActivityOrbAnimationPlanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: ActivityOrbAnimationPlan] = [:]

    func resolve(
        key: String,
        make: () -> ActivityOrbAnimationPlan
    ) -> ActivityOrbAnimationPlan {
        lock.lock()
        if let hit = storage[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let resolved = make()
        lock.lock()
        defer { lock.unlock() }
        if let racedHit = storage[key] {
            return racedHit
        }
        storage[key] = resolved
        return resolved
    }
}

private let activityOrbPresetCache = ActivityOrbPresetCache()
private let activityOrbAnimationPlanCache = ActivityOrbAnimationPlanCache()

func resolvePreset(mode: JinActivityOrbMode, size: JinActivityOrbSize) -> ResolvedActivityOrbPreset {
    let key = "\(mode.rawValue)-\(size.rawValue)"
    return activityOrbPresetCache.resolve(key: key) {
        let baked = ActivityOrbSpec.presets[mode]![size]!
        var opts = ActivityOrbSpec.baseProfiles[mode]!
        if baked.count != 1 {
            opts = scaleActivityOrbCounts(opts, baked.count)
        }
        if baked.size != 1 {
            opts = scaleActivityOrbRadii(opts, baked.size)
        }
        for (extraKey, value) in baked.extra {
            opts[extraKey] = value
        }
        return ResolvedActivityOrbPreset(mode: mode, speed: baked.speed, opts: opts)
    }
}
