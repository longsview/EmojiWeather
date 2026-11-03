import SwiftUI

/// One stream of emoji particles, like falling rain or sparkles shooting out of the sun.
struct EmitterSpec {
    enum Origin {
        /// Spawns along a horizontal line (above the screen by default) and falls (rain, snow).
        case top
        /// Spawns off the left edge (clouds, wind).
        case left
        /// Spawns anywhere in `band` and fades in and out (stars, sparkles).
        case scattered
        /// Spawns below the screen and rises (heat).
        case bottom
        /// Spawns at a point and flies outward (sun rays).
        case point(UnitPoint)
    }

    enum Landing {
        case none
        /// Breaks into a few tiny drops when it hits the bottom.
        case splash
        /// Stops at the bottom and slowly fades, like settling snow.
        case settle
    }

    var emoji: [String]
    /// Particles per second at full intensity.
    var rate: Double
    /// Font size in points.
    var size: ClosedRange<Double>
    /// Points per second.
    var speed: ClosedRange<Double> = 0...0
    /// Direction of travel in degrees. 0 is right, 90 is straight down, -90 is up.
    var angle: Double = 90
    var angleJitter: Double = 0
    /// Seconds.
    var lifetime: ClosedRange<Double> = 4...8
    var origin: Origin = .top
    /// Vertical band (0 is the top, 1 the bottom). For `.top` the lower bound is the start line.
    var band: ClosedRange<Double> = 0...1
    /// Horizontal spawn range for `.top`, as a fraction of the width.
    var xRange: ClosedRange<Double> = -0.3...1.3
    /// For `.point`: how far from the point particles appear, in points.
    var spawnRadius: Double = 0
    var landing: Landing = .none
    /// Side-to-side sway in points.
    var wobble: Double = 0
    /// Degrees per second.
    var spin: ClosedRange<Double> = 0...0
    var opacity: ClosedRange<Double> = 1...1
    /// Fade in at birth and out before death.
    var fades = false
    /// Downward acceleration in points per second squared.
    var gravity: Double = 0
    /// How many degrees tilting the phone fully sideways bends the stream.
    var tiltResponse: Double = 0
    /// Whether `SceneConditions.intensity` scales the rate.
    var followsIntensity = false
    /// For sun rays: particles leave only along these angles (degrees), so they form lines.
    var rays: [Double]? = nil
    /// Degrees per second the rays slowly turn.
    var rayRotation: Double = 0
}

/// A big emoji that stays roughly in place. Groups of these build shapes: a sun made of a ring of
/// emoji, a bank of storm clouds, a moon with orbiting stars.
struct HeroSpec {
    var emoji: String
    /// Anchor point as a fraction of the screen.
    var position: UnitPoint
    /// Offset from the anchor in points.
    var offset: CGSize = .zero
    var size: Double
    /// Degrees per second.
    var spin: Double = 0
    /// How much it breathes in and out, as a fraction of its size.
    var pulse: Double = 0
    /// Circles the anchor at this radius in points.
    var orbitRadius: Double = 0
    /// Degrees per second around the anchor.
    var orbitSpeed: Double = 0
    /// Starting angle on the orbit, also used to desync bob and pulse. Degrees.
    var phase: Double = 0
    /// Gentle up-and-down float in points.
    var bob: Double = 0
    var opacity: Double = 1
}

/// A full scene: background, particle streams, emoji shapes and optional lightning.
struct SceneSpec {
    var background: [Color] = [.white, .white]
    var emitters: [EmitterSpec]
    var heroes: [HeroSpec] = []
    /// Seconds between lightning strikes, or nil for none.
    var lightningInterval: ClosedRange<Double>? = nil
    /// Where bolts start, as a fraction of the screen height (just under the clouds).
    var lightningStart: Double = 0.24
    /// Seconds to simulate before the first frame so slow scenes (clouds, fog) start full.
    var prewarm: Double = 3
    var maxParticles = 300
}

/// Where the main emoji shape sits. The text sits below it.
private let artCenter = UnitPoint(x: 0.5, y: 0.27)
/// The sun follows the time of day: left at sunrise, top middle at noon, right at sunset,
/// on a gentle arc. The moon sits up in the right corner.
private func sunPosition(_ progress: Double) -> UnitPoint {
    UnitPoint(x: 0.15 + 0.7 * progress, y: 0.19 - 0.05 * sin(.pi * progress))
}
private let moonCorner = UnitPoint(x: 0.78, y: 0.17)
private let cloudLine = UnitPoint(x: 0.5, y: 0.17)

extension SceneSpec {
    static func make(for conditions: SceneConditions) -> SceneSpec {
        var spec = makeScene(for: conditions)
        spec.background = conditions.sky.background(for: conditions.scene)
        // Skymoji+ scene packs and the person's own emoji.
        SceneStyle.apply(to: &spec)
        return spec
    }

    private static func makeScene(for conditions: SceneConditions) -> SceneSpec {
        let wind = conditions.windDrift
        // Rain leans up to 30° with the wind. Angles below 90° travel toward the right.
        let rainAngle = 90 - wind * 30

        // The time of day picks the sun or the moon, whatever the scene's name says.
        let isNight = conditions.sky == .night
        var scene = conditions.scene
        switch scene {
        case .sunny, .hot: if isNight { scene = .clearNight }
        case .clearNight: if !isNight { scene = .sunny }
        default: break
        }

        switch scene {
        case .partlyCloudy:
            let drift = 1 + abs(wind) * 2
            let anchor = isNight ? moonCorner : sunPosition(conditions.sunProgress)
            // Puffy clouds drawn in front of the lower half of the sun or moon, so it peeks out
            // from behind them.
            let clouds = [
                HeroSpec(emoji: "☁️", position: anchor, offset: CGSize(width: -34, height: 38), size: 96, phase: 0, bob: 4),
                HeroSpec(emoji: "☁️", position: anchor, offset: CGSize(width: 44, height: 46), size: 80, phase: 140, bob: 3),
            ]
            let driftingClouds = EmitterSpec(
                emoji: ["☁️"], rate: 0.12, size: 40...62, speed: (14 * drift)...(24 * drift), angle: 0,
                lifetime: 55...75, origin: .left, band: 0.34...0.58, opacity: 0.85...1
            )
            if isNight {
                return SceneSpec(
                    emitters: [
                        EmitterSpec(
                            emoji: ["⭐️", "✨"], rate: 3.5, size: 7...16, lifetime: 2.5...6,
                            origin: .scattered, band: 0.02...0.98, fades: true
                        ),
                        driftingClouds,
                    ],
                    heroes: [HeroSpec(emoji: "🌙", position: moonCorner, size: 110, pulse: 0.03, bob: 4)] + clouds,
                    prewarm: 30
                )
            }
            return SceneSpec(
                emitters: [sunRays(emoji: ["✨"], at: anchor), driftingClouds],
                heroes: [HeroSpec(emoji: "☀️", position: anchor, size: 150, spin: 4, pulse: 0.04)] + clouds,
                prewarm: 30
            )

        case .sunny:
            return SceneSpec(
                emitters: [
                    // Rays of sparkles streaming out of the sun in the corner.
                    sunRays(emoji: ["✨"], at: sunPosition(conditions.sunProgress)),
                    EmitterSpec(
                        emoji: ["☁️"], rate: 0.05, size: 44...64, speed: 12...20, angle: 0,
                        lifetime: 60...80, origin: .left, band: 0.5...0.62, opacity: 0.9...1
                    ),
                ],
                heroes: [HeroSpec(emoji: "☀️", position: sunPosition(conditions.sunProgress), size: 160, spin: 4, pulse: 0.04)],
                prewarm: 30
            )

        case .hot:
            return SceneSpec(
                emitters: [
                    sunRays(emoji: ["✨", "🔥"], at: sunPosition(conditions.sunProgress)),
                    EmitterSpec(
                        emoji: ["🔥"], rate: 3, size: 14...24, speed: 30...70, angle: -90,
                        angleJitter: 8, lifetime: 4...7, origin: .bottom, wobble: 10, fades: true
                    ),
                ],
                heroes: [HeroSpec(emoji: "☀️", position: sunPosition(conditions.sunProgress), size: 175, spin: 5, pulse: 0.07)],
                prewarm: 5
            )

        case .clearNight:
            return SceneSpec(
                emitters: [
                    // Stars twinkle in and out all over the sky.
                    EmitterSpec(
                        emoji: ["⭐️", "⭐️", "✨"], rate: 7, size: 7...18, lifetime: 2.5...6,
                        origin: .scattered, band: 0.02...0.98, fades: true
                    ),
                    // Now and then a comet streaks down-left, head first (the ☄️ glyph's tail
                    // points up and right). 🌠 is drawn as a framed tile, so it looked like a box.
                    EmitterSpec(
                        emoji: ["☄️"], rate: 0.1, size: 24...32, speed: 380...480, angle: 145,
                        lifetime: 3...3, band: 0...0, xRange: 0.4...1.2
                    ),
                    // A few clouds drift by, like the odd cloud on a sunny day (Mostly Clear).
                    EmitterSpec(
                        emoji: ["☁️"], rate: 0.05, size: 44...64, speed: 12...20, angle: 0,
                        lifetime: 60...80, origin: .left, band: 0.5...0.62, opacity: 0.85...1
                    ),
                ],
                heroes: [HeroSpec(emoji: "🌙", position: moonCorner, size: 115, pulse: 0.03, bob: 4)],
                prewarm: 30
            )

        case .thunderstorm:
            return SceneSpec(
                emitters: [
                    EmitterSpec(
                        emoji: ["💧", "💧", "⛈️"], rate: 70, size: 12...22, speed: 520...720,
                        angle: rainAngle, angleJitter: 3, lifetime: 3...3, band: 0.2...0.2,
                        xRange: -0.2...1.2, landing: .splash, tiltResponse: 25, followsIntensity: true
                    ),
                ],
                heroes: cloudBank(front: "⛈️", frontCount: 4),
                lightningInterval: 3...8,
                prewarm: 1
            )

        case .rain:
            return SceneSpec(
                emitters: [
                    EmitterSpec(
                        emoji: ["💧"], rate: 110, size: 10...18, speed: 450...650,
                        angle: rainAngle, angleJitter: 2, lifetime: 3...3, band: 0.2...0.2,
                        xRange: -0.2...1.2, landing: .splash, tiltResponse: 25, followsIntensity: true
                    ),
                ],
                heroes: cloudBank(front: "🌧️", frontCount: 3),
                prewarm: 1
            )

        case .snow:
            return SceneSpec(
                emitters: [
                    EmitterSpec(
                        emoji: ["❄️"], rate: 28, size: 10...28, speed: 40...90,
                        angle: 90 - wind * 20, angleJitter: 12, lifetime: 14...20, band: 0.18...0.18,
                        landing: .settle, wobble: 18, spin: -40...40, tiltResponse: 35, followsIntensity: true
                    ),
                ],
                heroes: cloudBank(front: "🌨️", frontCount: 3),
                prewarm: 12
            )

        case .cloudy:
            let drift = 1 + abs(wind) * 2
            return SceneSpec(
                emitters: [
                    EmitterSpec(
                        emoji: ["☁️"], rate: 0.25, size: 36...60, speed: (18 * drift)...(30 * drift), angle: 0,
                        lifetime: 50...70, origin: .left, band: 0.38...0.6, opacity: 0.8...1
                    ),
                ],
                heroes: cloudBank(front: "☁️", frontCount: 4, anchor: UnitPoint(x: 0.5, y: 0.24)),
                prewarm: 40
            )

        case .windy:
            return SceneSpec(
                emitters: [
                    EmitterSpec(
                        emoji: ["💨"], rate: 3.5, size: 24...46, speed: 260...420, angle: 0,
                        angleJitter: 6, lifetime: 3...3, origin: .left, band: 0.1...0.9
                    ),
                    EmitterSpec(
                        emoji: ["🍃", "🍂"], rate: 2, size: 16...26, speed: 150...260, angle: 4,
                        angleJitter: 10, lifetime: 4...4, origin: .left, band: 0.1...0.9,
                        wobble: 22, spin: -220...220
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "🌬️", position: UnitPoint(x: 0.38, y: 0.27), size: 150, pulse: 0.06, bob: 5),
                ],
                prewarm: 3
            )

        case .foggy:
            return SceneSpec(
                emitters: [
                    EmitterSpec(
                        emoji: ["🌫️"], rate: 0.5, size: 90...170, speed: 8...16, angle: 0,
                        lifetime: 70...100, origin: .left, band: 0...0.7, opacity: 0.35...0.6
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "🌫️", position: artCenter, offset: CGSize(width: -60, height: 0), size: 130, phase: 0, bob: 6, opacity: 0.9),
                    HeroSpec(emoji: "🌫️", position: artCenter, offset: CGSize(width: 60, height: 20), size: 110, phase: 120, bob: 6, opacity: 0.8),
                ],
                prewarm: 60
            )
        }
    }

    // MARK: - Emoji shapes

    /// Twelve straight rays of small emoji flowing out of the sun and slowly turning.
    private static func sunRays(emoji: [String], at sun: UnitPoint) -> EmitterSpec {
        EmitterSpec(
            emoji: emoji, rate: 34, size: 10...17, speed: 75...90, angle: 0, angleJitter: 1.5,
            lifetime: 2.6...3.2, origin: .point(sun), spawnRadius: 100, fades: true,
            rays: stride(from: 0.0, to: 360.0, by: 30.0).map { $0 }, rayRotation: 4
        )
    }

    /// A puffy bank of ☁️ with a front row of weather clouds (⛈️, 🌧️, 🌨️) that float gently.
    private static func cloudBank(front: String, frontCount: Int, anchor: UnitPoint = cloudLine) -> [HeroSpec] {
        let width = 300.0
        let backCount = 7
        let back: [HeroSpec] = (0..<backCount).map { index in
            let t = Double(index) / Double(backCount - 1)
            let hump = sin(t * .pi)
            return HeroSpec(
                emoji: "☁️", position: anchor,
                offset: CGSize(width: (t - 0.5) * width, height: -hump * 36),
                size: 62 + hump * 40, phase: Double(index) * 47, bob: 3
            )
        }
        let frontRow: [HeroSpec] = (0..<frontCount).map { index in
            let t = frontCount == 1 ? 0.5 : Double(index) / Double(frontCount - 1)
            return HeroSpec(
                emoji: front, position: anchor,
                offset: CGSize(width: (t - 0.5) * width * 0.7, height: 24),
                size: 74, phase: Double(index) * 83 + 20, bob: 5
            )
        }
        return back + frontRow
    }
}
