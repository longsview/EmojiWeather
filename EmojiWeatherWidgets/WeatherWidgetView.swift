import AppIntents
import SwiftUI
import WidgetKit

/// Picks the layout for the widget's size, or the locked / empty states.
struct WeatherWidgetView: View {
    let entry: WeatherEntry

    @Environment(\.widgetFamily) private var family

    private var sky: SkyMode { entry.weather?.skyMode ?? .day }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family.isAccessory {
                    Color.clear
                } else {
                    LinearGradient(
                        colors: sky.background(for: entry.weather?.weatherScene ?? .sunny),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !entry.isUnlocked {
            LockedWidgetView(family: family)
        } else if let place = entry.place, let weather = entry.weather {
            switch family {
            case .accessoryCircular:
                CircularWidgetView(entry: entry, weather: weather)
            case .accessoryRectangular:
                RectangularWidgetView(entry: entry, place: place, weather: weather)
            case .accessoryInline:
                Text("\(weather.weatherScene.emoji) \(place.name) \(weather.temperature.shortTemperature)")
            case .systemMedium:
                HomeWidgetView(entry: entry, place: place, weather: weather, layout: .medium)
            case .systemLarge:
                HomeWidgetView(entry: entry, place: place, weather: weather, layout: .large)
            default:
                HomeWidgetView(entry: entry, place: place, weather: weather, layout: .small)
            }
        } else {
            EmptyWidgetView(family: family, hasPlace: entry.place != nil)
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}

// MARK: - Home Screen

/// The app's look in a box: the scene's emoji in the corner with a few scattered extras,
/// then the city, local time and temperature.
private struct HomeWidgetView: View {
    enum Layout { case small, medium, large }

    let entry: WeatherEntry
    let place: WidgetPlace
    let weather: WidgetWeather
    let layout: Layout

    private var sky: SkyMode { weather.skyMode }

    var body: some View {
        Group {
            layoutBody
        }
        .foregroundStyle(sky.textColor)
        // Widgets render dates with the environment's time zone, so set it to the place's.
        .environment(\.timeZone, place.timeZone)
    }

    /// Back and next, pinned to the right edge so they never cover the temperature.
    @ViewBuilder
    private var placeButtons: some View {
        if entry.isCycling {
            VStack(spacing: 8) {
                PlaceStepButton(direction: .previous, tint: sky.textColor)
                PlaceStepButton(direction: .next, tint: sky.textColor)
            }
            .padding(.trailing, 8)
        }
    }

    /// Room the text leaves for the buttons.
    private var buttonInset: CGFloat { entry.isCycling ? 34 : 0 }

    @ViewBuilder
    private var layoutBody: some View {
        switch layout {
        case .small:
            sceneCard(textInset: buttonInset)
                .overlay(alignment: .trailing) { placeButtons.padding(.top, 30) }
        case .medium:
            HStack(spacing: 0) {
                sceneCard(textInset: 0)
                HourlyStrip(hours: Array(weather.hours.prefix(5)), timeZone: place.timeZone)
                    .padding(.trailing, 14 + buttonInset)
                    .padding(.vertical, 16)
            }
            .overlay(alignment: .trailing) { placeButtons }
        case .large:
            VStack(spacing: 0) {
                sceneCard(textInset: buttonInset)
                    .overlay(alignment: .trailing) { placeButtons.padding(.top, 40) }
                    .frame(maxHeight: .infinity)
                VStack(spacing: 12) {
                    HourlyStrip(hours: Array(weather.hours.prefix(6)), timeZone: place.timeZone)
                    Divider().overlay(sky.textColor.opacity(0.15))
                    DailyRows(days: weather.days, timeZone: place.timeZone)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func sceneCard(textInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SceneDecor(scene: weather.weatherScene, compact: layout == .small)

            VStack(alignment: .leading, spacing: 0) {
                Text(place.name)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, 44)
                Text(entry.date, format: Date.FormatStyle(timeZone: place.timeZone).hour().minute())
                    .id(place.id)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .opacity(0.7)

                Spacer(minLength: 0)

                Text(weather.temperature.shortTemperature)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(weather.condition)
                        .lineLimit(1)
                    if layout != .small, let high = weather.high, let low = weather.low {
                        Text("↑\(high.shortTemperature) ↓\(low.shortTemperature)")
                            .opacity(0.7)
                    }
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .padding(.trailing, textInset)
            }
            .foregroundStyle(sky.textColor)
            .shadow(color: sky.haloColor, radius: 4)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The scene's big emoji in the top-right corner (like the app's sun and moon) with a few
/// smaller pieces scattered around it.
private struct SceneDecor: View {
    let scene: WeatherScene
    let compact: Bool

    private var hero: String {
        switch scene {
        case .thunderstorm: "⛈️"
        case .rain: "🌧️"
        case .snow: "🌨️"
        case .sunny: "☀️"
        case .clearNight: "🌙"
        case .cloudy: "☁️"
        case .windy: "🌬️"
        case .foggy: "🌫️"
        case .hot: "🥵"
        }
    }

    private var bits: [String] {
        switch scene {
        case .thunderstorm: ["⚡️", "💧", "⚡️", "💧"]
        case .rain: ["💧", "💧", "☂️", "💧"]
        case .snow: ["❄️", "❄️", "☃️", "❄️"]
        case .sunny: ["✨", "✨", "✨"]
        case .clearNight: ["⭐️", "✨", "⭐️", "✨"]
        case .cloudy: ["☁️", "☁️"]
        case .windy: ["🍃", "🍂", "🍃"]
        case .foggy: ["🌫️", "🌫️"]
        case .hot: ["🔥", "😎", "🔥"]
        }
    }

    /// Fixed spots, so the widget doesn't jump around between updates.
    private static let spots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.52, 0.30, 18), (0.78, 0.62, 16), (0.66, 0.46, 13), (0.58, 0.80, 12),
    ]

    var body: some View {
        GeometryReader { proxy in
            let heroSize: CGFloat = compact ? 52 : 60
            Text(hero)
                .font(.system(size: heroSize))
                .position(x: proxy.size.width - heroSize * 0.42, y: heroSize * 0.42)
            ForEach(Array(bits.enumerated()), id: \.offset) { index, bit in
                let spot = Self.spots[index % Self.spots.count]
                Text(bit)
                    .font(.system(size: spot.size))
                    .opacity(0.8)
                    .rotationEffect(.degrees(Double(index) * 17 - 20))
                    .position(x: proxy.size.width * spot.x, y: proxy.size.height * spot.y)
            }
        }
    }
}

private struct HourlyStrip: View {
    let hours: [WidgetWeather.Hour]
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 0) {
            ForEach(hours, id: \.date) { hour in
                VStack(spacing: 4) {
                    Text(hour.date, format: Date.FormatStyle(timeZone: timeZone).hour())
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .opacity(0.6)
                    Text(hour.emoji).font(.system(size: 22))
                    Text(hour.temperature.shortTemperature)
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DailyRows: View {
    let days: [WidgetWeather.Day]
    let timeZone: TimeZone

    var body: some View {
        VStack(spacing: 6) {
            ForEach(days, id: \.date) { day in
                HStack {
                    Text(day.date, format: Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
                        .frame(width: 44, alignment: .leading)
                    Text(day.emoji)
                    Spacer()
                    Text(day.low.shortTemperature).opacity(0.6)
                    Text(day.high.shortTemperature)
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.system(.footnote, design: .rounded, weight: .semibold))
            }
        }
    }
}

// MARK: - Lock Screen

private struct CircularWidgetView: View {
    let entry: WeatherEntry
    let weather: WidgetWeather

    var body: some View {
        CycleButton(enabled: entry.isCycling) {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(weather.weatherScene.emoji).font(.system(size: 22))
                    Text(weather.temperature.shortTemperature)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                }
            }
        }
    }
}

private struct RectangularWidgetView: View {
    let entry: WeatherEntry
    let place: WidgetPlace
    let weather: WidgetWeather

    var body: some View {
        CycleButton(enabled: entry.isCycling) {
            HStack(spacing: 8) {
                Text(weather.weatherScene.emoji)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        Text(place.name)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1)
                        if entry.isCycling {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.heavy))
                                .opacity(0.6)
                        }
                    }
                    Text("\(weather.temperature.shortTemperature) \(weather.condition)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    if let high = weather.high, let low = weather.low {
                        Text("↑\(high.shortTemperature) ↓\(low.shortTemperature)")
                            .font(.system(.caption, design: .rounded))
                            .opacity(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Shared pieces

/// Wraps Lock Screen content in the "next place" button when the widget steps through places.
private struct CycleButton<Content: View>: View {
    let enabled: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if enabled {
            Button(intent: StepPlaceIntent(forward: true)) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct PlaceStepButton: View {
    enum Direction { case previous, next }

    let direction: Direction
    let tint: Color

    var body: some View {
        Button(intent: StepPlaceIntent(forward: direction == .next)) {
            Image(systemName: direction == .next ? "chevron.right" : "chevron.left")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .next ? "Next place" : "Previous place")
    }
}

private struct LockedWidgetView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("✨ EmojiWeather+")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text("✨").font(.title2)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("✨ EmojiWeather+").font(.headline)
                Text("Unlock widgets in the app").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: 6) {
                Text("✨").font(.system(size: 44))
                Text("EmojiWeather+")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                Text("Unlock widgets in the app")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.black)
            .padding()
        }
    }
}

private struct EmptyWidgetView: View {
    let family: WidgetFamily
    let hasPlace: Bool

    private var message: String {
        hasPlace ? "Loading weather…" : "Open EmojiWeather to add a place"
    }

    var body: some View {
        if family.isAccessory {
            Text(family == .accessoryInline ? "EmojiWeather" : message)
                .font(.caption)
        } else {
            VStack(spacing: 6) {
                Text("🌤️").font(.system(size: 40))
                Text(message)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.black)
            .padding()
        }
    }
}

#Preview("Small", as: .systemSmall) {
    EmojiWeatherWidget()
} timeline: {
    WeatherEntry.sample
}

#Preview("Medium", as: .systemMedium) {
    EmojiWeatherWidget()
} timeline: {
    WeatherEntry.sample
}

#Preview("Large", as: .systemLarge) {
    EmojiWeatherWidget()
} timeline: {
    WeatherEntry.sample
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    EmojiWeatherWidget()
} timeline: {
    WeatherEntry.sample
}
