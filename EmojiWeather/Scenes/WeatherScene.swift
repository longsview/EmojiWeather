import SwiftUI
import WeatherKit

/// The animated emoji scenes. Each WeatherKit condition maps to one of these.
enum WeatherScene: String, CaseIterable, Identifiable, Sendable {
    case thunderstorm
    case rain
    case snow
    case sunny
    case clearNight
    /// Sun or moon (by the time of day) with clouds drifting past.
    case partlyCloudy
    case cloudy
    case windy
    case foggy
    case hot

    var id: String { rawValue }

    init(condition: WeatherCondition, isDaylight: Bool) {
        switch condition {
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms,
             .strongStorms, .tropicalStorm, .hurricane:
            self = .thunderstorm
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle,
             .freezingRain, .hail, .sleet, .wintryMix:
            self = .rain
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .frigid:
            self = .snow
        case .foggy, .haze, .smoky, .blowingDust:
            self = .foggy
        case .windy, .breezy:
            self = .windy
        case .hot:
            self = isDaylight ? .hot : .clearNight
        case .cloudy, .mostlyCloudy:
            self = .cloudy
        case .partlyCloudy:
            self = .partlyCloudy
        case .clear, .mostlyClear:
            self = isDaylight ? .sunny : .clearNight
        @unknown default:
            self = isDaylight ? .sunny : .cloudy
        }
    }

    var title: String {
        switch self {
        case .thunderstorm: String(localized: "Thunderstorm")
        case .rain: String(localized: "Rain")
        case .snow: String(localized: "Snow")
        case .sunny: String(localized: "Sunny")
        case .clearNight: String(localized: "Clear Night")
        case .partlyCloudy: String(localized: "Partly Cloudy")
        case .cloudy: String(localized: "Cloudy")
        case .windy: String(localized: "Windy")
        case .foggy: String(localized: "Fog")
        case .hot: String(localized: "Heat")
        }
    }

    var emoji: String {
        switch self {
        case .thunderstorm: "⛈️"
        case .rain: "🌧️"
        case .snow: "❄️"
        case .sunny: "☀️"
        case .clearNight: "🌙"
        case .partlyCloudy: "⛅️"
        case .cloudy: "☁️"
        case .windy: "💨"
        case .foggy: "🌫️"
        case .hot: "🥵"
        }
    }

    /// A short, playful line under the temperature. (Foundation Models can personalize this later.)
    var tagline: String {
        switch self {
        case .thunderstorm: String(localized: "Stay in. The sky's putting on a show. ⚡️")
        case .rain: String(localized: "Umbrella weather. ☂️")
        case .snow: String(localized: "Bundle up, it's snowing. 🧣")
        case .sunny: String(localized: "Sunglasses on. 😎")
        case .clearNight: String(localized: "Clear skies. Go find a star. 🔭")
        case .partlyCloudy: String(localized: "A little sun, a little cloud. ⛅️")
        case .cloudy: String(localized: "A soft, gray kind of day.")
        case .windy: String(localized: "Hold on to your hat. 🎩")
        case .foggy: String(localized: "Low visibility. Take it slow.")
        case .hot: String(localized: "Stay cool and drink some water. 🥤")
        }
    }

    /// True for scenes that show the sun or the moon. Which one depends on the time of day,
    /// not the weather: the sun by day and at sunrise and sunset, the moon at night.
    var showsSunOrMoon: Bool {
        switch self {
        case .sunny, .clearNight, .hot, .partlyCloudy: true
        default: false
        }
    }

    /// The scene's emoji at a time of day: the moon at night for clear and partly cloudy skies.
    func emoji(in sky: SkyMode) -> String {
        switch self {
        case .sunny, .clearNight: sky == .night ? "🌙" : "☀️"
        case .hot: sky == .night ? "🌙" : "🥵"
        case .partlyCloudy: sky == .night ? "🌙" : "⛅️"
        default: emoji
        }
    }

    /// The tagline at a time of day, so a clear night doesn't say "Sunglasses on".
    func tagline(in sky: SkyMode) -> String {
        switch self {
        case .sunny, .clearNight, .hot:
            sky == .night ? WeatherScene.clearNight.tagline : (self == .clearNight ? WeatherScene.sunny.tagline : tagline)
        case .partlyCloudy:
            sky == .night ? String(localized: "A few clouds keeping the moon company. 🌙") : tagline
        default:
            tagline
        }
    }

    /// A single emoji for the hourly and daily rows. Finer-grained than the scenes.
    static func emoji(for condition: WeatherCondition, isDaylight: Bool = true) -> String {
        switch condition {
        case .mostlyClear, .partlyCloudy:
            return isDaylight ? "🌤️" : "🌙"
        case .mostlyCloudy:
            return isDaylight ? "🌥️" : "☁️"
        case .sunShowers, .drizzle:
            return isDaylight ? "🌦️" : "🌧️"
        case .hail, .sleet, .freezingRain, .freezingDrizzle, .wintryMix:
            return "🧊"
        case .hurricane, .tropicalStorm:
            return "🌀"
        case .frigid:
            return "🥶"
        case .smoky, .blowingDust, .haze:
            return "🌫️"
        default:
            return WeatherScene(condition: condition, isDaylight: isDaylight).emoji
        }
    }
}

/// The inputs a scene needs: which scene, plus real weather values that change how it moves.
struct SceneConditions: Equatable, Sendable {
    var scene: WeatherScene
    /// 0...1. Drives how many drops or flakes fall.
    var intensity: Double = 0.5
    /// -1...1. Positive means the wind blows toward the right of the screen.
    var windDrift: Double = 0

    /// Day (white), sunrise/sunset (gradient) or night (dark).
    var sky: SkyMode = .day

    /// 0 at sunrise, 0.5 at solar noon, 1 at sunset. Moves the sun across the top of the screen.
    var sunProgress: Double = 0.1

    init(scene: WeatherScene, intensity: Double = 0.5, windDrift: Double = 0, sky: SkyMode = .day, sunProgress: Double = 0.1) {
        self.scene = scene
        self.intensity = intensity
        self.windDrift = windDrift
        self.sky = sky
        self.sunProgress = sunProgress
    }

    init(current: CurrentWeather, today: DayWeather? = nil) {
        // The time of day decides the sky (background, sun or moon); the weather decides the rest.
        // Sunrise and sunset count as day, so the low sun shows on the golden sky.
        sky = SkyMode(current: current, today: today)
        scene = WeatherScene(condition: current.condition, isDaylight: sky != .night)

        if let sunrise = today?.sun.sunrise, let sunset = today?.sun.sunset, sunset > sunrise {
            let progress = current.date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
            // Rounded so the scene isn't rebuilt every refresh for a tiny change.
            sunProgress = (min(max(progress, 0), 1) * 50).rounded() / 50
        }

        // WeatherKit reports precipitation as a speed; convert to millimeters per hour.
        let millimetersPerHour = current.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000
        // About 8 mm/h is heavy rain, so treat that as full intensity.
        let rawIntensity = millimetersPerHour > 0 ? millimetersPerHour / 8 : 0.5
        intensity = (min(max(rawIntensity, 0.2), 1) * 100).rounded() / 100

        let windKmh = current.wind.speed.converted(to: .kilometersPerHour).value
        let fromDegrees = current.wind.direction.converted(to: .degrees).value
        // Wind "from" the west (180° to 360°) blows toward the east, which is screen-right.
        let sign: Double = (fromDegrees > 180 && fromDegrees < 360) ? 1 : -1
        windDrift = (sign * min(windKmh, 50) / 50 * 100).rounded() / 100
    }
}

/// The look of the page for the time of day.
enum SkyMode: String, CaseIterable, Identifiable, Sendable {
    case day
    /// Within about 40 minutes of sunrise or sunset.
    case golden
    case night

    var id: String { rawValue }

    /// How close to sunrise or sunset counts as golden hour.
    static let goldenWindow: TimeInterval = 40 * 60

    init(current: CurrentWeather, today: DayWeather?) {
        let now = current.date
        if let sun = today?.sun {
            let events = [sun.sunrise, sun.sunset].compactMap { $0 }
            if events.contains(where: { abs(now.timeIntervalSince($0)) < Self.goldenWindow }) {
                self = .golden
                return
            }
        }
        self = current.isDaylight ? .day : .night
    }

    var title: String {
        switch self {
        case .day: "Day"
        case .golden: "Sunrise / Sunset"
        case .night: "Night"
        }
    }

    /// Top-to-bottom background.
    var background: [Color] {
        switch self {
        case .day: [.white, .white]
        case .golden: [Color(hex: 0x2E3A78), Color(hex: 0xA9558F), Color(hex: 0xFF8A5C), Color(hex: 0xFFC46B)]
        case .night: [Color(hex: 0x0A0F24), Color(hex: 0x1C2650)]
        }
    }

    /// The background for a scene. Only clear and hot days are white; every other daytime
    /// scene gets a soft grey, a shade darker for storms.
    func background(for scene: WeatherScene) -> [Color] {
        guard self == .day else { return background }
        switch scene {
        case .sunny, .hot, .clearNight, .partlyCloudy:
            return background
        case .thunderstorm:
            return [Color(hex: 0xE4E7EB), Color(hex: 0xD5D9DF)]
        case .cloudy, .foggy, .rain, .snow, .windy:
            return [Color(hex: 0xEEF0F3), Color(hex: 0xE2E5EA)]
        }
    }

    var isDark: Bool { self != .day }

    var textColor: Color { isDark ? .white : .black }

    /// Halo behind text so it stays readable over moving emoji.
    var haloColor: Color {
        switch self {
        case .day: .white
        case .golden: .black.opacity(0.3)
        case .night: .black.opacity(0.5)
        }
    }
}

extension EnvironmentValues {
    /// The current page's sky, so text and controls can match it.
    @Entry var skyMode: SkyMode = .day
}
