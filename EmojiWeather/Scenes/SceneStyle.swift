import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Scene packs

/// Skymoji+ scene packs. A pack keeps the real weather and adds seasonal emoji on top:
/// bats among the stars at Halloween, presents drifting down in December, butterflies in spring.
enum ScenePack: String, CaseIterable, Identifiable, Sendable {
    /// Just the weather.
    case classic
    /// Picks the pack for today's date.
    case seasonal
    case halloween
    case autumn
    case holidays
    case spring
    case summer

    var id: Self { self }

    /// The packs a person can pick themselves, after Classic and Follow the seasons.
    static let themed: [ScenePack] = [.halloween, .autumn, .holidays, .spring, .summer]

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .seasonal: String(localized: "Follow the seasons")
        case .halloween: String(localized: "Halloween")
        case .autumn: String(localized: "Autumn leaves")
        case .holidays: String(localized: "Winter holidays")
        case .spring: String(localized: "Spring bloom")
        case .summer: String(localized: "Summer days")
        }
    }

    /// A few of the pack's emoji, for the picker.
    var preview: String {
        switch self {
        case .classic: "☀️☁️🌧️❄️"
        case .seasonal: "🎃🍁🎁🌸🍉"
        case .halloween: "🎃🦇👻🍬"
        case .autumn: "🍁🍂🍄🌰"
        case .holidays: "🎁🎄☃️🌟"
        case .spring: "🌸🦋🌷🐝"
        case .summer: "🍉🌴🍦🐚"
        }
    }

    /// For `.seasonal`, the pack for the date. Northern-hemisphere seasons, holidays by date.
    func resolved(for date: Date = .now) -> ScenePack {
        guard self == .seasonal else { return self }
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        let day = (parts.month ?? 1) * 100 + (parts.day ?? 1)
        switch day {
        case 1001...1101: return .halloween
        case 922...1130: return .autumn
        case 1201...1231, 101...106: return .holidays
        case 320...531: return .spring
        case 601...921: return .summer
        default: return .classic
        }
    }

    /// Emoji added in small numbers to streams that already use the key emoji.
    fileprivate var mixIns: [String: [String]] {
        switch self {
        case .classic, .seasonal: [:]
        case .halloween: ["⭐️": ["🦇"], "✨": ["🍬"], "🍃": ["🎃"], "🍂": ["🎃"], "💨": ["👻"]]
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

// MARK: - Your own emoji

/// The emoji a Skymoji+ member can swap for their own (or a Genmoji).
enum EmojiSlot: String, CaseIterable, Identifiable, Codable, Sendable {
    case sun, moon, cloud, raindrop, snowflake, star, sparkle

    var id: Self { self }

    /// The emoji the scenes use by default.
    var original: String {
        switch self {
        case .sun: "☀️"
        case .moon: "🌙"
        case .cloud: "☁️"
        case .raindrop: "💧"
        case .snowflake: "❄️"
        case .star: "⭐️"
        case .sparkle: "✨"
        }
    }

    var title: String {
        switch self {
        case .sun: String(localized: "Sun")
        case .moon: String(localized: "Moon")
        case .cloud: String(localized: "Clouds")
        case .raindrop: String(localized: "Raindrops")
        case .snowflake: String(localized: "Snowflakes")
        case .star: String(localized: "Stars")
        case .sparkle: String(localized: "Sparkles and sun rays")
        }
    }
}

/// What a slot is set to: a plain emoji, or a Genmoji saved as an image.
/// Stored as a string: the emoji itself, or "genmoji:<id>".
enum SceneEmoji: Hashable, Sendable {
    case emoji(String)
    case genmoji(id: String)

    static let genmojiPrefix = "genmoji:"

    init(_ raw: String) {
        if raw.hasPrefix(Self.genmojiPrefix) {
            self = .genmoji(id: String(raw.dropFirst(Self.genmojiPrefix.count)))
        } else {
            self = .emoji(raw)
        }
    }

    /// The key scenes draw with. `EmojiImageCache` knows how to draw both kinds.
    var raw: String {
        switch self {
        case .emoji(let emoji): emoji
        case .genmoji(let id): Self.genmojiPrefix + id
        }
    }
}

// MARK: - The style scenes are drawn with

/// The pack and emoji swaps that apply to every scene. Both are Skymoji+ features, so they
/// apply only while Skymoji+ is active; otherwise scenes are always Classic.
enum SceneStyle {
    static let packKey = "settings.scenePack"
    static let customEmojiKey = "settings.customEmoji"
    private static let plusActiveKey = "scene.plusActive"

    /// Kept in step with purchases by `PurchaseManager`.
    static var plusActive: Bool {
        get { SharedStore.defaults.bool(forKey: plusActiveKey) }
        set {
            guard newValue != plusActive else { return }
            SharedStore.defaults.set(newValue, forKey: plusActiveKey)
        }
    }

    static var chosenPack: ScenePack {
        get { SharedStore.defaults.string(forKey: packKey).flatMap(ScenePack.init(rawValue:)) ?? .classic }
        set { SharedStore.defaults.set(newValue.rawValue, forKey: packKey) }
    }

    /// Slot → emoji. Stored as JSON text so `@AppStorage` can watch it.
    static var customEmoji: [EmojiSlot: SceneEmoji] {
        get { decodeCustom(SharedStore.defaults.string(forKey: customEmojiKey) ?? "") }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value.raw) })
            let data = (try? JSONEncoder().encode(raw)) ?? Data()
            SharedStore.defaults.set(String(decoding: data, as: UTF8.self), forKey: customEmojiKey)
            GenmojiStore.removeUnused(keeping: Set(newValue.values.compactMap {
                if case .genmoji(let id) = $0 { id } else { nil }
            }))
        }
    }

    static func decodeCustom(_ json: String) -> [EmojiSlot: SceneEmoji] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var result: [EmojiSlot: SceneEmoji] = [:]
        for (key, value) in raw {
            if let slot = EmojiSlot(rawValue: key) { result[slot] = SceneEmoji(value) }
        }
        return result
    }

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
            case .star: lookup["🌠"] = value.raw
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

    /// Changes whenever anything that affects how scenes look changes. Views that show scenes
    /// use it as an identity so they rebuild.
    static func styleKey(pack: String, customJSON: String, plus: Bool) -> String {
        let custom = customJSON == "{}" ? "" : customJSON
        guard plus, pack != ScenePack.classic.rawValue || !custom.isEmpty else { return "classic" }
        return "\(pack)|\(custom)"
    }
}

// MARK: - Genmoji files

/// Genmoji are images, so they're saved as files in the App Group container and drawn from there.
enum GenmojiStore {
    private static var folder: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("Genmoji", isDirectory: true)
    }

    private static func url(for id: String) -> URL? {
        folder?.appendingPathComponent("\(id).img")
    }

    /// Saves the Genmoji's image data and returns its id.
    static func save(_ imageData: Data) -> String? {
        guard let folder else { return nil }
        let id = UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try imageData.write(to: folder.appendingPathComponent("\(id).img"), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    static func data(for id: String) -> Data? {
        url(for: id).flatMap { try? Data(contentsOf: $0) }
    }

    static func removeUnused(keeping ids: Set<String>) {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where !ids.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    #if canImport(UIKit)
    static func image(for id: String) -> UIImage? {
        data(for: id).flatMap(UIImage.init(data:))
    }
    #endif
}
