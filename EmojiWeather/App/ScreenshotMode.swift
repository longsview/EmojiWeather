#if DEBUG
import Foundation
import WeatherKit

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

/// Sample weather that matches a forced scene, shared by the iPhone, iPad and Watch screenshots.
extension WeatherScene {
    /// Sample temperatures, set in °F and shown in the reader's unit (a French screenshot says 24°, not 75°).
    var sampleFahrenheit: Double {
        switch self {
        case .thunderstorm: 71
        case .rain: 58
        case .snow: 28
        case .sunny: 75
        case .clearNight: 62
        case .partlyCloudy: 68
        case .cloudy: 64
        case .windy: 60
        case .foggy: 55
        case .hot: 103
        }
    }

    var sampleHighFahrenheit: Double {
        switch self {
        case .hot: 106
        case .snow: 31
        default: 78
        }
    }

    var sampleLowFahrenheit: Double {
        switch self {
        case .hot: 84
        case .snow: 19
        default: 52
        }
    }

    var sampleTemperature: String { Measurement(value: sampleFahrenheit, unit: UnitTemperature.fahrenheit).shortTemperature }
    var sampleHigh: String { Measurement(value: sampleHighFahrenheit, unit: UnitTemperature.fahrenheit).shortTemperature }
    var sampleLow: String { Measurement(value: sampleLowFahrenheit, unit: UnitTemperature.fahrenheit).shortTemperature }

    var sampleCondition: WeatherCondition {
        switch self {
        case .thunderstorm: .thunderstorms
        case .rain: .rain
        case .snow: .snow
        case .sunny, .clearNight: .clear
        case .partlyCloudy: .partlyCloudy
        case .cloudy: .cloudy
        case .windy: .windy
        case .foggy: .foggy
        case .hot: .hot
        }
    }

}
#endif
