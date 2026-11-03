import Foundation
import WeatherKit

/// Data the app shares with the widgets through the App Group: the places to show, the latest
/// weather for each, and whether the user has Skymoji+. Compiled into both targets.
enum SharedStore {
    static let appGroup = "group.com.longsview.EmojiWeather"

    private static let placesKey = "widget.places.v1"
    private static let hasPlusKey = "widget.hasPlus"
    private static let cycleIndexKey = "widget.cycleIndex"
    private static func weatherKey(_ placeID: String) -> String { "widget.weather.v1.\(placeID)" }

    /// One instance for the process; creating a suite per read makes cfprefsd noisy.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var places: [WidgetPlace] {
        get { decode([WidgetPlace].self, forKey: placesKey) ?? [] }
        set { encode(newValue, forKey: placesKey) }
    }

    static var hasPlus: Bool {
        get { defaults.bool(forKey: hasPlusKey) }
        set { defaults.set(newValue, forKey: hasPlusKey) }
    }

    /// Which place the "next place" button has stepped to. Shared by all widgets.
    static var cycleIndex: Int {
        get { defaults.integer(forKey: cycleIndexKey) }
        set { defaults.set(newValue, forKey: cycleIndexKey) }
    }

    static func weather(for placeID: String) -> WidgetWeather? {
        decode(WidgetWeather.self, forKey: weatherKey(placeID))
    }

    static func setWeather(_ weather: WidgetWeather, for placeID: String) {
        encode(weather, forKey: weatherKey(placeID))
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// A place as the widgets see it: the current location or a saved city.
struct WidgetPlace: Codable, Hashable, Identifiable, Sendable {
    static let currentLocationID = "current"

    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?

    var isCurrentLocation: Bool { id == Self.currentLocationID }

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }
}

/// A small, Codable copy of the weather a widget needs.
struct WidgetWeather: Codable, Hashable, Sendable {
    struct Hour: Codable, Hashable, Sendable {
        var date: Date
        var temperature: Measurement<UnitTemperature>
        var emoji: String
    }

    struct Day: Codable, Hashable, Sendable {
        var date: Date
        var high: Measurement<UnitTemperature>
        var low: Measurement<UnitTemperature>
        var emoji: String
    }

    var temperature: Measurement<UnitTemperature>
    var high: Measurement<UnitTemperature>?
    var low: Measurement<UnitTemperature>?
    var condition: String
    /// `WeatherScene` raw value.
    var scene: String
    /// `SkyMode` raw value.
    var sky: String
    var hours: [Hour]
    var days: [Day] = []
    var fetchedAt: Date

    var weatherScene: WeatherScene { WeatherScene(rawValue: scene) ?? .cloudy }
    var skyMode: SkyMode { SkyMode(rawValue: sky) ?? .day }

    init(current: CurrentWeather, hourly: [HourWeather], daily: [DayWeather], fetchedAt: Date) {
        temperature = current.temperature
        high = daily.first?.highTemperature
        low = daily.first?.lowTemperature
        condition = current.condition.description
        scene = WeatherScene(condition: current.condition, isDaylight: current.isDaylight).rawValue
        sky = SkyMode(current: current, today: daily.first).rawValue
        hours = hourly
            .filter { $0.date > fetchedAt.addingTimeInterval(-30 * 60) }
            .prefix(6)
            .map { Hour(date: $0.date, temperature: $0.temperature, emoji: WeatherScene.emoji(for: $0.condition, isDaylight: $0.isDaylight)) }
        days = daily.prefix(5).map {
            Day(date: $0.date, high: $0.highTemperature, low: $0.lowTemperature, emoji: WeatherScene.emoji(for: $0.condition))
        }
        self.fetchedAt = fetchedAt
    }

    init(
        temperature: Measurement<UnitTemperature>,
        high: Measurement<UnitTemperature>?,
        low: Measurement<UnitTemperature>?,
        condition: String,
        scene: WeatherScene,
        sky: SkyMode,
        hours: [Hour],
        days: [Day] = [],
        fetchedAt: Date
    ) {
        self.temperature = temperature
        self.high = high
        self.low = low
        self.condition = condition
        self.scene = scene.rawValue
        self.sky = sky.rawValue
        self.hours = hours
        self.days = days
        self.fetchedAt = fetchedAt
    }
}

extension Measurement where UnitType == UnitTemperature {
    /// "72°" in the unit chosen in Settings (or the region's unit). Like Apple Weather, only the
    /// degree sign is shown; the unit letter lives in Settings.
    var shortTemperature: String {
        let value = converted(to: DisplaySettings.temperatureUnit).value
        return value.formatted(.number.precision(.fractionLength(0))) + "°"
    }

    /// "72 degrees" style text for VoiceOver.
    var spokenTemperature: String {
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        return converted(to: DisplaySettings.temperatureUnit).formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: number))
    }
}
