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
    case thanksgiving
    case autumn
    case holidays
    case spring
    case summer

    var id: Self { self }

    /// The packs a person can pick themselves, after Classic and Follow the seasons.
    static let themed: [ScenePack] = [.halloween, .thanksgiving, .autumn, .holidays, .spring, .summer]

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .seasonal: String(localized: "Follow the seasons")
        case .halloween: String(localized: "Halloween")
        case .thanksgiving: String(localized: "Thanksgiving")
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
        case .thanksgiving: "🦃🥧🌽🍁"
        case .autumn: "🍁🍂🍄🌰"
        case .holidays: "🎁🎄☃️🌟"
        case .spring: "🌸🦋🌷🐝"
        case .summer: "🍉🌴🍦🐚"
        }
    }

    /// For `.seasonal`, the pack for the date and the person's region (Settings > General >
    /// Language & Region). Thanksgiving follows the US date (the fourth Thursday of November,
    /// through that weekend). South of the equator, spring, summer and autumn swap places.
    func resolved(for date: Date = .now, region: String? = Locale.current.region?.identifier) -> ScenePack {
        guard self == .seasonal else { return self }
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = (parts.month ?? 1) * 100 + (parts.day ?? 1)

        // Holidays come first: they're on the same dates everywhere the app marks them.
        switch day {
        case 1001...1101: return .halloween
        case 1201...1231, 101...106: return .holidays
        default: break
        }
        if region == "US", let year = parts.year, let thanksgiving = Self.usThanksgiving(year: year, calendar: calendar) {
            let start = (11 * 100) + 2
            let end = 11 * 100 + thanksgiving + 3  // Through the Sunday after.
            if (start...end).contains(day) { return .thanksgiving }
        }

        let southern = region.map(Self.southernRegions.contains) ?? false
        switch day {
        case 922...1130: return southern ? .spring : .autumn
        case 320...531: return southern ? .autumn : .spring
        case 601...921: return southern ? .classic : .summer
        case 107...319: return southern ? .summer : .classic
        default: return .classic
        }
    }

    /// The day of November that US Thanksgiving falls on: the fourth Thursday.
    static func usThanksgiving(year: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        var components = DateComponents(year: year, month: 11)
        components.weekday = 5  // Thursday
        components.weekdayOrdinal = 4
        return calendar.date(from: components).map { calendar.component(.day, from: $0) }
    }

    /// Regions mostly south of the equator, where the seasons are the other way round.
    private static let southernRegions: Set<String> = [
        "AR", "AU", "BO", "BR", "BW", "CL", "FJ", "LS", "MG", "MU", "MW", "MZ", "NA", "NZ",
        "PE", "PY", "SZ", "UY", "ZA", "ZM", "ZW",
    ]

    /// Two of the pack's emoji that widgets and complications sprinkle in.
    var accents: [String] {
        switch self {
        case .classic, .seasonal: []
        case .halloween: ["🎃", "🦇"]
        case .thanksgiving: ["🦃", "🍁"]
        case .autumn: ["🍁", "🍂"]
        case .holidays: ["🎁", "🎄"]
        case .spring: ["🌸", "🦋"]
        case .summer: ["🍉", "🌴"]
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
    static let plusActiveKey = "scene.plusActive"

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


    /// The pack showing today, or Classic when Skymoji+ isn't active.
    static var activePack: ScenePack {
        plusActive ? chosenPack.resolved() : .classic
    }

    /// The person's pick for one emoji, for widgets and complications, which draw single emoji
    /// instead of scenes. Nil when it isn't swapped (or Skymoji+ isn't active).
    static func custom(for emoji: String, in swaps: [EmojiSlot: SceneEmoji]? = nil) -> SceneEmoji? {
        guard plusActive else { return nil }
        let swaps = swaps ?? customEmoji
        let slot: EmojiSlot? = switch emoji {
        case "☀️", "🌞": .sun
        case "🌙", "🌛", "🌜", "🌕": .moon
        case "☁️": .cloud
        case "💧": .raindrop
        case "❄️": .snowflake
        case "⭐️", "🌟", "🌠", "☄️": .star
        case "✨": .sparkle
        default: EmojiSlot.allCases.first { $0.original == emoji }
        }
        return slot.flatMap { swaps[$0] }
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

    /// Moves a Genmoji file sent from the phone into place on the watch.
    static func store(fileAt source: URL, id: String) {
        guard let folder, let destination = url(for: id) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
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

// MARK: - Drawing one emoji

/// One emoji in a widget or complication, swapped for the person's own pick (emoji or Genmoji)
/// when they have one.
struct SceneEmojiText: View {
    let emoji: String
    let size: CGFloat
    var swaps: [EmojiSlot: SceneEmoji]? = nil

    var body: some View {
        switch SceneStyle.custom(for: emoji, in: swaps) {
        case .genmoji(let id)?:
            #if canImport(UIKit)
            if let image = GenmojiStore.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 1.1, height: size * 1.1)
            } else {
                Text(verbatim: emoji).font(.system(size: size))
            }
            #else
            Text(verbatim: emoji).font(.system(size: size))
            #endif
        case .emoji(let custom)?:
            Text(verbatim: custom).font(.system(size: size))
        case nil:
            Text(verbatim: emoji).font(.system(size: size))
        }
    }
}

// MARK: - Sending the style to the watch

/// What the phone sends the watch over WatchConnectivity: the scene pack, your own emoji,
/// whether Skymoji+ is active, and the units and clock, so the watch matches the phone.
enum StyleSync {
    private enum Key {
        static let pack = "pack"
        static let custom = "custom"
        static let plus = "plus"
        static let temperature = "temperature"
        static let clock = "clock"
        static let animate = "animate"
    }
    /// File transfer metadata key that carries a Genmoji's id.
    static let genmojiMetadataKey = "genmoji"
    /// Bumped on the watch when a Genmoji file arrives, so scenes redraw with it.
    static let genmojiVersionKey = "scene.genmojiVersion"

    static func context() -> [String: Any] {
        let defaults = SharedStore.defaults
        return [
            Key.pack: defaults.string(forKey: SceneStyle.packKey) ?? ScenePack.classic.rawValue,
            Key.custom: defaults.string(forKey: SceneStyle.customEmojiKey) ?? "",
            Key.plus: SceneStyle.plusActive,
            Key.temperature: defaults.string(forKey: DisplaySettings.temperatureKey) ?? TemperatureSetting.automatic.rawValue,
            Key.clock: defaults.string(forKey: DisplaySettings.clockKey) ?? ClockSetting.automatic.rawValue,
            Key.animate: defaults.object(forKey: DisplaySettings.animateScenesKey) as? Bool ?? true,
        ]
    }

    /// On the watch: saves what the phone sent. Only changed values are written, so views
    /// watching these settings don't redraw for nothing.
    static func apply(_ context: [String: Any]) {
        let defaults = SharedStore.defaults
        func set(_ key: String, _ value: String?) {
            guard let value, defaults.string(forKey: key) != value else { return }
            defaults.set(value, forKey: key)
        }
        set(SceneStyle.packKey, context[Key.pack] as? String)
        set(SceneStyle.customEmojiKey, context[Key.custom] as? String)
        set(DisplaySettings.temperatureKey, context[Key.temperature] as? String)
        set(DisplaySettings.clockKey, context[Key.clock] as? String)
        if let plus = context[Key.plus] as? Bool { SceneStyle.plusActive = plus }
        if let animate = context[Key.animate] as? Bool,
           defaults.object(forKey: DisplaySettings.animateScenesKey) as? Bool != animate {
            defaults.set(animate, forKey: DisplaySettings.animateScenesKey)
        }
        GenmojiStore.removeUnused(keeping: genmojiIDs)
    }

    /// The Genmoji the person's emoji use right now.
    static var genmojiIDs: Set<String> {
        Set(SceneStyle.customEmoji.values.compactMap {
            if case .genmoji(let id) = $0 { id } else { nil }
        })
    }
}
