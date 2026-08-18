// Mode frames for the curated activity-orb subset.
// MIT © 2026 Jakub Antalik — transcribed from ThinkingOrbsKit
// (Orbits.swift / Lattice.swift / Strands.swift).

import Foundation

func activityOrbFrameOrbits(_ size: Double, _ t: Double, _ o: [String: Double]) -> ActivityOrbFrame {
    let cx = size / 2
    let cy = size / 2
    let radius = (size / 2) * 0.82
    let projector = ActivityOrbProjector(yaw: t * 0.12, tilt: 0.3, cx: cx, cy: cy, scale: 1)
    let rs = activityOrbRadiusScale(size, pow: o["rsPow"] ?? 0.6)

    var dots: [ActivityOrbDot] = []
    let orbitN = Int(o["orbitN"] ?? 12)
    let ghostN = Int(o["ghostN"] ?? 40)
    let particles = Int(o["particles"] ?? 3)

    for orb in 0..<orbitN {
        let h1 = activityOrbHashD(Double(orb), 1.7)
        let h2 = activityOrbHashD(Double(orb), 5.2)
        let h3 = activityOrbHashD(Double(orb), 8.9)
        let ro = radius * (0.45 + 0.52 * h1)
        let th = h1 * 2 * Double.pi
        let phi = acos(2 * h2 - 1)
        let nx = sin(phi) * cos(th)
        let ny = cos(phi)
        let nz = sin(phi) * sin(th)
        var ux = -ny
        var uy = nx
        let uz = 0.0
        let ul = Swift.max(1e-6, (ux * ux + uy * uy).squareRoot())
        ux /= ul
        uy /= ul
        let vx = ny * uz - nz * uy
        let vy = nz * ux - nx * uz
        let vz = nx * uy - ny * ux
        let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)

        for k in 0..<ghostN {
            let a = (Double(k) / Double(ghostN)) * 2 * Double.pi
            let (px, py, z) = projector(
                (ux * cos(a) + vx * sin(a)) * ro,
                (uy * cos(a) + vy * sin(a)) * ro,
                (uz * cos(a) + vz * sin(a)) * ro
            )
            let depth = (z / ro + 1) / 2
            dots.append(ActivityOrbDot(
                x: px, y: py, z: z,
                r: (o["ghostR"] ?? 0.9) * rs,
                white: 0.72,
                a: (o["ghostA"] ?? 0.5) * (0.4 + 0.6 * depth)
            ))
        }

        for m in 0..<particles {
            let a = t * speed + (Double(m) / Double(particles)) * 2 * Double.pi + h2 * 6
            let (px, py, z) = projector(
                (ux * cos(a) + vx * sin(a)) * ro,
                (uy * cos(a) + vy * sin(a)) * ro,
                (uz * cos(a) + vz * sin(a)) * ro
            )
            let depth = (z / ro + 1) / 2
            dots.append(ActivityOrbDot(
                x: px, y: py, z: z,
                r: ((o["partR"] ?? 1.2) + (o["partRDepth"] ?? 1.6) * depth) * rs,
                white: 0.3 - 0.22 * depth,
                a: 1
            ))
        }
    }
    return activityOrbFinalizeFrame(
        dots,
        [],
        rMin: o["rMin"] ?? 0.3,
        sortByDepth: size > JinActivityOrbSize.inline.value
    )
}

func activityOrbFrameGlobe(_ size: Double, _ t: Double, _ o: [String: Double]) -> ActivityOrbFrame {
    let spin = 0.5
    let cx = size / 2
    let cy = size / 2
    let radius = (size / 2) * 0.82
    let tilt = 0.4 + 0.06 * sin(t * 0.35)
    let projector = ActivityOrbProjector(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius)
    let scan = t * (spin + (1.7 - spin) * (o["scanMul"] ?? 1))
    let rs = activityOrbRadiusScale(size, pow: o["rsPow"] ?? 0.6)
    let dimBase = o["dimBase"] ?? 1

    var dots: [ActivityOrbDot] = []
    let latRings = Int(o["latRings"] ?? 17)
    let lonDensity = o["lonDensity"] ?? 44
    for li in 0...latRings {
        let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * Double.pi
        let cosLat = cos(lat)
        let sinLat = sin(lat)
        let lonCount = Swift.max(1, Int((abs(cosLat) * lonDensity).rounded(.toNearestOrAwayFromZero)))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * Double.pi
            let (px, py, z) = projector(cosLat * cos(lon), sinLat, cosLat * sin(lon))
            let depth = (z + 1) / 2
            let d = activityOrbAngleDelta(lon + t * spin, scan)
            let boost = exp(-(d * d) / 0.18) * Swift.max(0, z)
            dots.append(ActivityOrbDot(
                x: px, y: py, z: z,
                r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (o["rBoost"] ?? 1) * boost) * rs,
                white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth,
                a: dimBase + (1 - dimBase) * Swift.min(1, boost)
            ))
        }
    }
    return activityOrbFinalizeFrame(
        dots,
        [],
        rMin: o["rMin"] ?? 0.3,
        sortByDepth: size > JinActivityOrbSize.inline.value
    )
}

func activityOrbFrameWave(_ size: Double, _ t: Double, _ o: [String: Double]) -> ActivityOrbFrame {
    let cx = size / 2
    let cy = size / 2
    let radius = (size / 2) * 0.874
    let projector = ActivityOrbProjector(yaw: t * 0.18, tilt: 0.38, cx: cx, cy: cy, scale: 1)
    let rs = activityOrbRadiusScale(size, pow: o["rsPow"] ?? 0.6)

    var dots: [ActivityOrbDot] = []
    let rings = Int(o["rings"] ?? 15)
    let lonDensity = o["lonDensity"] ?? 40
    for ri in 0...rings {
        let lat = -Double.pi / 2 + (Double(ri) / Double(rings)) * Double.pi
        let cosLat = cos(lat)
        let sinLat = sin(lat)
        let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
        let rr = radius * (0.88 + 0.105 * w)
        let lonCount = Swift.max(1, Int((abs(cosLat) * lonDensity).rounded(.toNearestOrAwayFromZero)))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * Double.pi
            let (px, py, z) = projector(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
            let depth = (z / radius + 1) / 2
            let crest = Swift.max(0, w)
            dots.append(ActivityOrbDot(
                x: px, y: py, z: z,
                r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth) * (1 + 0.4 * crest) * rs,
                white: 0.66 - 0.56 * depth - 0.1 * crest,
                a: 1
            ))
        }
    }
    return activityOrbFinalizeFrame(
        dots,
        [],
        rMin: o["rMin"] ?? 0.3,
        sortByDepth: size > JinActivityOrbSize.inline.value
    )
}

func activityOrbFrameRibbon(_ size: Double, _ t: Double, _ o: [String: Double]) -> ActivityOrbFrame {
    let cx = size / 2
    let cy = size / 2
    let radius = (size / 2) * 0.78
    let spin = o["spin"] ?? 1
    let camTilt = 0.3
    let faceOn = (o["faceOn"] ?? 0) != 0
    let projector = ActivityOrbProjector(yaw: t * 0.1 * spin, tilt: camTilt, cx: cx, cy: cy, scale: 1)
    let rs = activityOrbRadiusScale(size, pow: o["rsPow"] ?? 0.6)

    var dots: [ActivityOrbDot] = []
    let ghostN = Int(o["ghostN"] ?? 0)
    if ghostN > 0 {
        for i in 0..<ghostN {
            let d = activityOrbFibDir(i, ghostN)
            let (px, py, z) = projector(d.0 * radius, d.1 * radius, d.2 * radius)
            let depth = (z / radius + 1) / 2
            dots.append(ActivityOrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
    }

    let ya = t * 0.24 * spin
    let ta = faceOn ? -camTilt : 0.55 + 0.3 * sin(t * 0.18) * spin
    let ux = cos(ya)
    let uy = 0.0
    let uz = sin(ya)
    let vx = -uz * sin(ta)
    let vy = cos(ta)
    let vz = ux * sin(ta)
    let nx = uy * vz - uz * vy
    let ny = uz * vx - ux * vz
    let nz = ux * vy - uy * vx

    let wobMul = o["wobMul"] ?? 1
    let wobAmp = 0.23 * wobMul
    let baseR = faceOn ? radius / (1 + 0.85 * wobAmp) : radius

    let baseLanes = o["lanes"] ?? 5
    let segs = Int(o["segs"] ?? 88)
    let lanes = Swift.max(1, Int((baseLanes * (o["bandMul"] ?? 1)).rounded(.toNearestOrAwayFromZero)))
    for w in 0..<lanes {
        let laneOff = (Double(w) - Double(lanes - 1) / 2) * 0.075
        let edge = abs(Double(w) - Double(lanes - 1) / 2) / Swift.max(1, Double(lanes - 1) / 2)
        for k in 0..<segs {
            let a = (Double(k) / Double(segs)) * 2 * Double.pi
            let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22)
                + 0.07 * sin(a * 5 + t * 1.1)) * wobMul
            let radial = faceOn ? 1 + wob : 1
            let off = faceOn ? laneOff : laneOff + wob
            let x = ux * cos(a) + vx * sin(a) + nx * off
            let y = uy * cos(a) + vy * sin(a) + ny * off
            let z = uz * cos(a) + vz * sin(a) + nz * off
            let length = (x * x + y * y + z * z).squareRoot()
            let rr = baseR * radial
            let (px, py, zr) = projector((x / length) * rr, (y / length) * rr, (z / length) * rr)
            let depth = (zr / radius + 1) / 2
            dots.append(ActivityOrbDot(
                x: px, y: py, z: zr,
                r: ((o["rBase"] ?? 1.1) + (o["rDepth"] ?? 1.7) * depth) * (1 - 0.25 * edge) * rs,
                white: 0.52 - 0.44 * depth + 0.18 * edge,
                a: 0.4 + 0.6 * depth
            ))
        }
    }
    return activityOrbFinalizeFrame(
        dots,
        [],
        rMin: o["rMin"] ?? 0.3,
        sortByDepth: size > JinActivityOrbSize.inline.value
    )
}

// MARK: - Rubik (solving)

/// Mid-rest of the scramble → click-back cycle. All move amounts are 0.
func activityOrbRubikRestInstant(moveCount: Double) -> Double {
    let count = Swift.max(1, Int(moveCount.rounded(.toNearestOrAwayFromZero)))
    let slotDur = 0.42
    let rest = 1.2
    return 2 * Double(count) * slotDur + rest / 2
}

private struct ActivityOrbRubikMove {
    let axis: Int
    let lo: Double
    let hi: Double
    let ang: Double
}

private func activityOrbRubikMoves(count: Int) -> [ActivityOrbRubikMove] {
    (0..<count).map { index in
        let i = Double(index)
        let axis = Swift.min(2, Int((activityOrbHashD(i, 2.3) * 3).rounded(.down)))
        let lo = -1.0 + 0.5 * Swift.min(3, (activityOrbHashD(i, 5.9) * 4).rounded(.down))
        let dir: Double = activityOrbHashD(i, 7.7) < 0.5 ? 1 : -1
        return ActivityOrbRubikMove(axis: axis, lo: lo, hi: lo + 0.5, ang: dir * Double.pi / 2)
    }
}

private func activityOrbRubikSolveCycle(
    time: Double,
    count: Int,
    slotDur: Double,
    rest: Double
) -> (amount: [Double], active: Int) {
    let cycle = 2 * Double(count) * slotDur + rest
    let tc = time.truncatingRemainder(dividingBy: cycle)
    var amount = Array(repeating: 0.0, count: count)
    var active = -1
    let scrambleWindow = 2 * Double(count) * slotDur
    guard tc < scrambleWindow else { return (amount, active) }

    let slot = Int((tc / slotDur).rounded(.down))
    let p = (tc - Double(slot) * slotDur) / slotDur
    let cl = Swift.min(1, p / 0.7)
    let eased = 1 - pow(1 - cl, 3)
    if slot < count {
        if slot > 0 {
            for i in 0..<slot { amount[i] = 1 }
        }
        amount[slot] = eased
        active = slot
    } else {
        let u = 2 * count - 1 - slot
        if u > 0 {
            for i in 0..<u { amount[i] = 1 }
        }
        if u >= 0, u < count {
            amount[u] = 1 - eased
            active = u
        }
    }
    return (amount, active)
}

private func activityOrbRubikApplyMoves(
    _ point: (Double, Double, Double),
    moves: [ActivityOrbRubikMove],
    amount: [Double],
    active: Int
) -> (Double, Double, Double, Bool) {
    var x = point.0
    var y = point.1
    var z = point.2
    var inActive = false
    for (index, move) in moves.enumerated() {
        guard amount[index] > 0 else { continue }
        let coord = move.axis == 0 ? x : (move.axis == 1 ? y : z)
        guard coord >= move.lo, coord < move.hi else { continue }
        if index == active { inActive = true }
        let a = move.ang * amount[index]
        let ca = cos(a)
        let sa = sin(a)
        if move.axis == 0 {
            let y2 = y * ca - z * sa
            z = y * sa + z * ca
            y = y2
        } else if move.axis == 1 {
            let x2 = x * ca + z * sa
            z = -x * sa + z * ca
            x = x2
        } else {
            let x2 = x * ca - y * sa
            y = x * sa + y * ca
            x = x2
        }
    }
    return (x, y, z, inActive)
}

/// solving — bands scramble in quarter turns, then click back.
func activityOrbFrameRubik(_ size: Double, _ t: Double, _ o: [String: Double]) -> ActivityOrbFrame {
    let cx = size / 2
    let cy = size / 2
    let radius = (size / 2) * 0.82
    let projector = ActivityOrbProjector(
        yaw: t * 0.55,
        tilt: 0.35 + 0.1 * sin(t * 0.9),
        cx: cx,
        cy: cy,
        scale: radius
    )
    let rs = activityOrbRadiusScale(size, pow: o["rsPow"] ?? 0.6)
    let moveCount = Swift.max(1, Int((o["moveCount"] ?? 14).rounded(.toNearestOrAwayFromZero)))
    let moves = activityOrbRubikMoves(count: moveCount)
    let cycle = activityOrbRubikSolveCycle(time: t, count: moveCount, slotDur: 0.42, rest: 1.2)

    var dots: [ActivityOrbDot] = []
    let latRings = Int(o["latRings"] ?? 15)
    let lonDensity = o["lonDensity"] ?? 40
    for li in 0...latRings {
        let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * Double.pi
        let cosLat = cos(lat)
        let sinLat = sin(lat)
        let lonCount = Swift.max(1, Int((abs(cosLat) * lonDensity).rounded(.toNearestOrAwayFromZero)))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * Double.pi
            let (x, y, z, inActive) = activityOrbRubikApplyMoves(
                (cosLat * cos(lon), sinLat, cosLat * sin(lon)),
                moves: moves,
                amount: cycle.amount,
                active: cycle.active
            )
            let (px, py, zr) = projector(x, y, z)
            let depth = (zr + 1) / 2
            dots.append(ActivityOrbDot(
                x: px, y: py, z: zr,
                r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth
                    + (inActive ? (o["rActive"] ?? 0.3) : 0)) * rs,
                white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth
                    - (inActive ? 0.14 : 0),
                a: 1
            ))
        }
    }
    return activityOrbFinalizeFrame(
        dots,
        [],
        rMin: o["rMin"] ?? 0.3,
        sortByDepth: size > JinActivityOrbSize.inline.value
    )
}
