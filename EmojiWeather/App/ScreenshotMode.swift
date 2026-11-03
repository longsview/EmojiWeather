#if DEBUG
import Foundation

/// Debug-only launch arguments for App Store screenshots, so each shot is one `simctl launch`:
///
///     xcrun simctl launch booted com.longsview.EmojiWeather \
///       -SkymojiPlus YES -SkymojiScene rain -SkymojiSky day -SkymojiOpen forecast
///
/// - `-SkymojiPlus YES`: Skymoji+ unlocked (no ads, no watermark).
/// - `-SkymojiScene sunny|partlyCloudy|cloudy|rain|thunderstorm|snow|clearNight|windy|foggy|hot`:
///   every page shows that scene, with matching sample temperatures.
/// - `-SkymojiSky day|sunset|night`: the time of day.
/// - `-SkymojiTab weather|map|settings`: the first tab.
/// - `-SkymojiOpen forecast|quiz|quizSummary|share|paywall|scenePack`: opens that screen.
/// - `-SkymojiPack thanksgiving|halloween|autumn|holidays|spring|summer|seasonal|classic`.
/// - `-SkymojiCity Honolulu`: opens a saved city by name.
/// - `-SkymojiPlace Cupertino`: the name shown for My Location (no waiting for geocoding).
///
/// While any of these is set, the 🐞 menu is hidden and clocks show 9:41 (AM for day,
/// 6:41 PM for sunset, 9:41 PM for night).
enum ScreenshotMode {
    private static let defaults = UserDefaults.standard

    static var plus: Bool { defaults.bool(forKey: "SkymojiPlus") }

    static var scene: WeatherScene? {
        defaults.string(forKey: "SkymojiScene").flatMap(WeatherScene.init(rawValue:))
    }

    static var sky: SkyMode? {
        switch defaults.string(forKey: "SkymojiSky") {
        case "day": .day
        case "sunset", "golden": .golden
        case "night": .night
        default: nil
        }
    }

    static var tab: String? { defaults.string(forKey: "SkymojiTab") }
    static var open: String? { defaults.string(forKey: "SkymojiOpen") }
    static var pack: ScenePack? { defaults.string(forKey: "SkymojiPack").flatMap(ScenePack.init(rawValue:)) }
    static var city: String? { defaults.string(forKey: "SkymojiCity") }
    static var place: String? { defaults.string(forKey: "SkymojiPlace") }

    /// True when any screenshot argument was passed.
    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-Skymoji") }

    /// The time every clock shows in screenshot mode.
    static var fixedDate: Date? {
        guard isActive else { return nil }
        let hour = switch sky {
        case .golden: 18
        case .night: 21
        default: scene == .clearNight ? 21 : 9
        }
        return Calendar.current.date(bySettingHour: hour, minute: 41, second: 0, of: .now)
    }

    /// Where the sun sits for the fixed time: mid-morning, or low in the west at sunset.
    static var sunProgress: Double {
        sky == .golden ? 0.96 : 0.3
    }
}
#endif
