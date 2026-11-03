import Foundation

/// The user's choices from the Settings tab, stored in the App Group so the widgets follow them
/// too. "Automatic" follows the region (Settings > General > Language & Region).
enum TemperatureSetting: String, CaseIterable, Identifiable, Sendable {
    case automatic, celsius, fahrenheit
    var id: Self { self }
}

enum ClockSetting: String, CaseIterable, Identifiable, Sendable {
    case automatic, twelveHour, twentyFourHour
    var id: Self { self }
}

enum DisplaySettings {
    static let temperatureKey = "settings.temperature"
    static let clockKey = "settings.clock"
    static let animateScenesKey = "settings.animateScenes"

    static var temperature: TemperatureSetting {
        SharedStore.defaults.string(forKey: temperatureKey).flatMap(TemperatureSetting.init(rawValue:)) ?? .automatic
    }

    static var clock: ClockSetting {
        SharedStore.defaults.string(forKey: clockKey).flatMap(ClockSetting.init(rawValue:)) ?? .automatic
    }

    /// The unit the region uses for weather, for the "Automatic (°F)" label.
    static var regionTemperatureUnit: UnitTemperature {
        UnitTemperature(forLocale: .current, usage: .weather)
    }

    /// The unit temperatures are shown in.
    static var temperatureUnit: UnitTemperature {
        switch temperature {
        case .automatic: regionTemperatureUnit
        case .celsius: .celsius
        case .fahrenheit: .fahrenheit
        }
    }

    /// True when the region uses a 12-hour clock.
    static var regionUses12HourClock: Bool {
        switch Locale.current.hourCycle {
        case .oneToTwelve, .zeroToEleven: true
        default: false
        }
    }

    /// The current locale with the chosen clock applied. Used for every time on screen.
    static var locale: Locale {
        var components = Locale.Components(locale: .current)
        switch clock {
        case .automatic: break
        case .twelveHour: components.hourCycle = .oneToTwelve
        case .twentyFourHour: components.hourCycle = .zeroToTwentyThree
        }
        return Locale(components: components)
    }

    /// "9:41 PM" or "21:41" in a place's time zone.
    static func timeStyle(_ timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone).hour().minute().locale(locale)
    }

    /// "9 PM" or "21" for hourly forecasts.
    static func hourStyle(_ timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone).hour().locale(locale)
    }

    static func weekdayStyle(_ timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated).locale(locale)
    }
}
