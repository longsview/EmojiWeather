import SwiftUI

/// One stream of emoji particles, like falling rain or drifting clouds.
struct EmitterSpec {
    enum Origin {
        /// Spawns above the screen (rain, snow).
        case top
        /// Spawns off the left edge (clouds, wind).
        case left
        /// Spawns anywhere on screen and fades in and out (stars, sparkles).
        case scattered
        /// Spawns below the screen and rises (heat).
        case bottom
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
    /// Vertical band (0 is the top, 1 the bottom) for `.left` and `.scattered` origins.
    var band: ClosedRange<Double> = 0...1
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
}

/// A large emoji that stays in place, like the sun or moon.
struct HeroSpec {
    var emoji: String
    var position: UnitPoint
    var size: Double
    /// Degrees per second.
    var spin: Double = 0
    /// How much it breathes in and out, as a fraction of its size.
    var pulse: Double = 0
}

/// A full scene: background, particle streams, fixed emoji and optional lightning.
struct SceneSpec {
    var background: [Color]
    var emitters: [EmitterSpec]
    var heroes: [HeroSpec] = []
    /// Seconds between lightning strikes, or nil for none.
    var lightningInterval: ClosedRange<Double>? = nil
    /// Seconds to simulate before the first frame so slow scenes (clouds, fog) start full.
    var prewarm: Double = 3
    var maxParticles = 300
}

extension SceneSpec {
    static func make(for conditions: SceneConditions) -> SceneSpec {
        let wind = conditions.windDrift
        // Rain leans up to 30° with the wind. Angles below 90° travel toward the right.
        let rainAngle = 90 - wind * 30

        switch conditions.scene {
        case .thunderstorm:
            return SceneSpec(
                background: [Color(hex: 0x141A2A), Color(hex: 0x37405A)],
                emitters: [
                    EmitterSpec(
                        emoji: ["⛈️"], rate: 70, size: 14...24, speed: 520...720,
                        angle: rainAngle, angleJitter: 3, lifetime: 3...3, landing: .splash,
                        tiltResponse: 25, followsIntensity: true
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "⛈️", position: UnitPoint(x: 0.22, y: 0.07), size: 110, pulse: 0.03),
                    HeroSpec(emoji: "⛈️", position: UnitPoint(x: 0.78, y: 0.1), size: 90, pulse: 0.04),
                ],
                lightningInterval: 4...10,
                prewarm: 1
            )

        case .rain:
            return SceneSpec(
                background: [Color(hex: 0x34465C), Color(hex: 0x6E8094)],
                emitters: [
                    EmitterSpec(
                        emoji: ["💧"], rate: 110, size: 9...18, speed: 450...650,
                        angle: rainAngle, angleJitter: 2, lifetime: 3...3, landing: .splash,
                        tiltResponse: 25, followsIntensity: true
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "🌧️", position: UnitPoint(x: 0.25, y: 0.07), size: 100, pulse: 0.02),
                    HeroSpec(emoji: "🌧️", position: UnitPoint(x: 0.75, y: 0.09), size: 85, pulse: 0.03),
                ],
                prewarm: 1
            )

        case .snow:
            return SceneSpec(
                background: [Color(hex: 0x7D90AA), Color(hex: 0xC8D5E3)],
                emitters: [
                    EmitterSpec(
                        emoji: ["❄️"], rate: 26, size: 10...28, speed: 40...90,
                        angle: 90 - wind * 20, angleJitter: 12, lifetime: 14...20, landing: .settle,
                        wobble: 18, spin: -40...40, tiltResponse: 35, followsIntensity: true
                    ),
                ],
                prewarm: 12
            )

        case .sunny:
            return SceneSpec(
                background: [Color(hex: 0x3D9BF2), Color(hex: 0xA8E0FF)],
                emitters: [
                    EmitterSpec(
                        emoji: ["✨"], rate: 1.5, size: 10...20, lifetime: 1.5...3,
                        origin: .scattered, band: 0.05...0.6, fades: true
                    ),
                    EmitterSpec(
                        emoji: ["☁️"], rate: 0.07, size: 40...70, speed: 10...18, angle: 0,
                        lifetime: 70...90, origin: .left, band: 0.15...0.45, opacity: 0.85...1
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "☀️", position: UnitPoint(x: 0.74, y: 0.11), size: 150, spin: 6, pulse: 0.05),
                ],
                prewarm: 40
            )

        case .clearNight:
            return SceneSpec(
                background: [Color(hex: 0x080D22), Color(hex: 0x23305E)],
                emitters: [
                    EmitterSpec(
                        emoji: ["⭐️"], rate: 3, size: 6...14, lifetime: 2...5,
                        origin: .scattered, band: 0...0.7, fades: true
                    ),
                    EmitterSpec(
                        emoji: ["🌠"], rate: 0.08, size: 20...28, speed: 380...480, angle: 20,
                        lifetime: 3...3, origin: .left, band: 0.02...0.3
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "🌙", position: UnitPoint(x: 0.8, y: 0.1), size: 100, pulse: 0.02),
                ],
                prewarm: 4
            )

        case .cloudy:
            let drift = 1 + abs(wind) * 2
            return SceneSpec(
                background: [Color(hex: 0x8A9AA8), Color(hex: 0xC6D0D8)],
                emitters: [
                    EmitterSpec(
                        emoji: ["☁️"], rate: 0.3, size: 30...50, speed: (25 * drift)...(40 * drift), angle: 0,
                        lifetime: 60...80, origin: .left, band: 0.0...0.6, opacity: 0.55...0.75
                    ),
                    EmitterSpec(
                        emoji: ["☁️"], rate: 0.25, size: 70...120, speed: (12 * drift)...(24 * drift), angle: 0,
                        lifetime: 80...110, origin: .left, band: 0.0...0.5, opacity: 0.9...1
                    ),
                ],
                prewarm: 45
            )

        case .windy:
            return SceneSpec(
                background: [Color(hex: 0x66AECA), Color(hex: 0xB7E0EA)],
                emitters: [
                    EmitterSpec(
                        emoji: ["💨"], rate: 3.5, size: 24...46, speed: 260...420, angle: 0,
                        angleJitter: 6, lifetime: 3...3, origin: .left, band: 0.05...0.95
                    ),
                    EmitterSpec(
                        emoji: ["🍃", "🍂"], rate: 1.8, size: 16...26, speed: 150...260, angle: 4,
                        angleJitter: 10, lifetime: 4...4, origin: .left, band: 0.1...0.9,
                        wobble: 22, spin: -220...220
                    ),
                ],
                prewarm: 3
            )

        case .foggy:
            return SceneSpec(
                background: [Color(hex: 0x939DA6), Color(hex: 0xD2D7DB)],
                emitters: [
                    EmitterSpec(
                        emoji: ["🌫️"], rate: 0.45, size: 90...170, speed: 8...16, angle: 0,
                        lifetime: 70...100, origin: .left, band: 0...1, opacity: 0.3...0.55
                    ),
                ],
                prewarm: 60
            )

        case .hot:
            return SceneSpec(
                background: [Color(hex: 0xFF8A3D), Color(hex: 0xFFD36E)],
                emitters: [
                    EmitterSpec(
                        emoji: ["🔥"], rate: 4, size: 14...26, speed: 30...70, angle: -90,
                        angleJitter: 8, lifetime: 4...7, origin: .bottom, wobble: 10, fades: true
                    ),
                ],
                heroes: [
                    HeroSpec(emoji: "☀️", position: UnitPoint(x: 0.5, y: 0.12), size: 170, spin: 4, pulse: 0.08),
                ],
                prewarm: 5
            )
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
