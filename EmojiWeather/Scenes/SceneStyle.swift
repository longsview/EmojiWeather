import SwiftUI

// The scene-building half of scene packs and custom emoji. The settings and storage live in
// Shared/SceneStyleShared.swift so widgets and complications can read them too.

extension ScenePack {
    /// Emoji added in small numbers to streams that already use the key emoji.
    fileprivate var mixIns: [String: [String]] {
        switch self {
        case .classic, .seasonal: [:]
        case .halloween: ["⭐️": ["🦇"], "✨": ["🍬"], "🍃": ["🎃"], "🍂": ["🎃"], "💨": ["👻"]]
        case .thanksgiving: ["✨": ["🍂"], "🍃": ["🍁", "🍂"], "⭐️": ["🌽"]]
        case .autumn: ["🍃": ["🍁", "🍂"], "✨": ["🍂"]]
        case .holidays: ["⭐️": ["🌟"], "✨": ["🌟"], "❄️": ["⛄️"]]
        case .spring: ["✨": ["🌸"], "🍃": ["🌸", "🌷"], "⭐️": ["✨"]]
        case .summer: ["✨": ["🌻"], "🔥": ["🍉"]]
        }
    }

    /// One gentle extra stream that sets the mood whatever the weather.
    fileprivate var ambient: EmitterSpec? {
        switch self {
        case .classic, .seasonal:
            return nil
        case .halloween:
            // Bats and ghosts wobbling across the sky.
            return EmitterSpec(
                emoji: ["🦇", "🦇", "🎃", "👻", "🎃"], rate: 0.75, size: 20...34, speed: 45...85, angle: 0,
                angleJitter: 8, lifetime: 10...14, origin: .left, band: 0.05...0.75, wobble: 22, opacity: 0.85...1
            )
        case .thanksgiving:
            // Leaves, pies and corn tumbling down, with the odd turkey.
            return EmitterSpec(
                emoji: ["🍁", "🍂", "🦃", "🥧", "🌽", "🍁", "🦃"], rate: 0.6, size: 18...30, speed: 35...60,
                angleJitter: 14, lifetime: 18...24, band: 0...0, landing: .settle, wobble: 22,
                spin: -60...60, tiltResponse: 30
            )
        case .autumn:
            // Leaves tumbling down.
            return EmitterSpec(
                emoji: ["🍁", "🍂", "🍂", "🍁", "🍄"], rate: 0.6, size: 16...28, speed: 35...60,
                angleJitter: 14, lifetime: 18...24, band: 0...0, landing: .settle, wobble: 26,
                spin: -90...90, tiltResponse: 30
            )
        case .holidays:
            // Presents and trees floating down like slow snow.
            return EmitterSpec(
                emoji: ["🎁", "🎄", "☃️", "🔔", "🎁"], rate: 0.3, size: 18...28, speed: 28...50,
                angleJitter: 10, lifetime: 22...28, band: 0...0, landing: .settle, wobble: 16,
                spin: -30...30, tiltResponse: 30
            )
        case .spring:
            // Butterflies, bees and petals fluttering across.
            return EmitterSpec(
                emoji: ["🦋", "🌸", "🐝", "🌸", "🌷"], rate: 0.45, size: 16...28, speed: 35...70, angle: -4,
                angleJitter: 12, lifetime: 10...14, origin: .left, band: 0.25...0.9, wobble: 26, spin: -40...40
            )
        case .summer:
            // Beach things bobbing up from the bottom.
            return EmitterSpec(
                emoji: ["🍉", "🍦", "🌴", "🐚", "🕶️"], rate: 0.3, size: 18...30, speed: 25...45, angle: -90,
                angleJitter: 8, lifetime: 12...18, origin: .bottom, wobble: 14, fades: true
            )
        }
    }
}

extension SceneStyle {
    /// Adds the pack and swaps in the person's own emoji.
    static func apply(to spec: inout SceneSpec, date: Date = .now) {
        guard plusActive else { return }
        let pack = chosenPack.resolved(for: date)

        // Pack first, keyed by the original emoji, so swaps below don't hide the mix-ins.
        let mixIns = pack.mixIns
        if !mixIns.isEmpty {
            for index in spec.emitters.indices {
                let emoji = spec.emitters[index].emoji
                let extras = emoji.flatMap { mixIns[$0] ?? [] }
                guard !extras.isEmpty else { continue }
                // About one in four particles becomes a seasonal one.
                spec.emitters[index].emoji = emoji + emoji + emoji + extras
            }
        }
        if let ambient = pack.ambient {
            spec.emitters.append(ambient)
        }

        let swaps = customEmoji
        guard !swaps.isEmpty else { return }
        var lookup: [String: String] = [:]
        for (slot, value) in swaps {
            lookup[slot.original] = value.raw
            // Weather-specific cousins of the slot follow it too.
            switch slot {
            case .star: lookup["☄️"] = value.raw
            default: break
            }
        }
        for index in spec.emitters.indices {
            spec.emitters[index].emoji = spec.emitters[index].emoji.map { lookup[$0] ?? $0 }
        }
        for index in spec.heroes.indices {
            spec.heroes[index].emoji = lookup[spec.heroes[index].emoji] ?? spec.heroes[index].emoji
        }
    }
}
