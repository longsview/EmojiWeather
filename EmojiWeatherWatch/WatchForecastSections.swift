import SwiftUI
import WeatherKit

/// A rounded card that keeps text readable over the scene: frosted white by day, dark at night.
struct WatchCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.skyMode) private var sky

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .textCase(.uppercase)
                .opacity(0.7)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .foregroundStyle(sky.textColor)
        .background(sky.isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.8), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }
}

/// One hour in the hourly card: from WeatherKit, or sample data for screenshots.
struct WatchHour {
    var date: Date
    var condition: WeatherCondition
    var isDaylight: Bool
    var temperature: Measurement<UnitTemperature>
    var precipitationChance: Double

    init(date: Date, condition: WeatherCondition, isDaylight: Bool, temperature: Measurement<UnitTemperature>, precipitationChance: Double) {
        self.date = date
        self.condition = condition
        self.isDaylight = isDaylight
        self.temperature = temperature
        self.precipitationChance = precipitationChance
    }

    init(_ hour: HourWeather) {
        self.init(date: hour.date, condition: hour.condition, isDaylight: hour.isDaylight, temperature: hour.temperature, precipitationChance: hour.precipitationChance)
    }
}

/// One day in the 10-day card: from WeatherKit, or sample data for screenshots.
struct WatchDay {
    var date: Date
    var condition: WeatherCondition
    var lowTemperature: Measurement<UnitTemperature>
    var highTemperature: Measurement<UnitTemperature>
    var precipitationChance: Double

    init(date: Date, condition: WeatherCondition, lowTemperature: Measurement<UnitTemperature>, highTemperature: Measurement<UnitTemperature>, precipitationChance: Double) {
        self.date = date
        self.condition = condition
        self.lowTemperature = lowTemperature
        self.highTemperature = highTemperature
        self.precipitationChance = precipitationChance
    }

    init(_ day: DayWeather) {
        self.init(date: day.date, condition: day.condition, lowTemperature: day.lowTemperature, highTemperature: day.highTemperature, precipitationChance: day.precipitationChance)
    }
}

/// The next 12 hours, scrolling sideways.
struct WatchHourlySection: View {
    let hours: [WatchHour]
    let timeZone: TimeZone

    var body: some View {
        WatchCard(title: String(localized: "Hourly")) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(hours.prefix(12).enumerated()), id: \.offset) { index, hour in
                        let time = index == 0 ? String(localized: "Now") : hour.date.formatted(DisplaySettings.hourStyle(timeZone))
                        VStack(spacing: 3) {
                            Text(time)
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .opacity(0.8)
                            Text(verbatim: WeatherScene.emoji(for: hour.condition, isDaylight: hour.isDaylight))
                                .font(.title3)
                            Text(hour.temperature.shortTemperature)
                                .font(.system(.footnote, design: .rounded, weight: .bold))
                            if hour.precipitationChance >= 0.2 {
                                Text(hour.precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(time), \(hour.condition.description), \(hour.temperature.spokenTemperature)"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Today's conditions, two to a row, each with its own emoji.
struct WatchConditionsSection: View {
    let current: CurrentWeather
    let today: DayWeather?
    let timeZone: TimeZone

    private struct Tile: Identifiable {
        let emoji: String
        let title: String
        let value: String
        var id: String { title }
    }

    private var tiles: [Tile] {
        let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        var tiles = [
            Tile(emoji: "🌡️", title: String(localized: "Feels like"), value: current.apparentTemperature.shortTemperature),
            Tile(emoji: "🕶️", title: String(localized: "UV index"), value: "\(current.uvIndex.value) \(current.uvIndex.category.description)"),
            Tile(
                emoji: "🌬️", title: String(localized: "Wind"),
                value: current.wind.speed.formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
                    + " " + current.wind.compassDirection.abbreviation
            ),
            Tile(emoji: "💦", title: String(localized: "Humidity"), value: current.humidity.formatted(percent)),
        ]
        if let today {
            tiles.append(Tile(emoji: "☔️", title: String(localized: "Rain chance"), value: today.precipitationChance.formatted(percent)))
        }
        tiles.append(Tile(
            emoji: "👀", title: String(localized: "Visibility"),
            value: current.visibility.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        ))
        tiles.append(Tile(emoji: "💧", title: String(localized: "Dew point"), value: current.dewPoint.shortTemperature))
        tiles.append(Tile(
            emoji: "🧭", title: String(localized: "Pressure"),
            value: current.pressure.formatted(.measurement(width: .abbreviated, usage: .barometric, numberFormatStyle: .number.precision(.fractionLength(0))))
        ))
        if let today {
            let timeStyle = DisplaySettings.timeStyle(timeZone)
            if let sunrise = today.sun.sunrise {
                tiles.append(Tile(emoji: "🌅", title: String(localized: "Sunrise"), value: sunrise.formatted(timeStyle)))
            }
            if let sunset = today.sun.sunset {
                tiles.append(Tile(emoji: "🌇", title: String(localized: "Sunset"), value: sunset.formatted(timeStyle)))
            }
        }
        return tiles
    }

    var body: some View {
        WatchCard(title: String(localized: "Conditions")) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 10) {
                ForEach(tiles) { tile in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: tile.emoji).font(.body).accessibilityHidden(true)
                        Text(tile.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .textCase(.uppercase)
                            .opacity(0.7)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(tile.value)
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Ten days, each with a temperature bar like Apple Weather: the bar spans the day's low to high
/// on the scale of the whole ten days.
struct WatchDailySection: View {
    let days: [WatchDay]
    let timeZone: TimeZone

    var body: some View {
        let unit = DisplaySettings.temperatureUnit
        let lows = days.map { $0.lowTemperature.converted(to: unit).value }
        let highs = days.map { $0.highTemperature.converted(to: unit).value }
        let minimum = lows.min() ?? 0
        let maximum = max(highs.max() ?? 1, minimum + 1)

        WatchCard(title: String(localized: "10-day forecast")) {
            VStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let name = index == 0 ? String(localized: "Today") : day.date.formatted(DisplaySettings.weekdayStyle(timeZone))
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if day.precipitationChance >= 0.2 {
                                Text(day.precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.cyan)
                            }
                            Text(verbatim: WeatherScene.emoji(for: day.condition))
                                .font(.body)
                        }
                        HStack(spacing: 4) {
                            Text(day.lowTemperature.shortTemperature)
                                .opacity(0.7)
                                .frame(width: 30, alignment: .leading)
                            TemperatureBar(
                                low: (lows[index] - minimum) / (maximum - minimum),
                                high: (highs[index] - minimum) / (maximum - minimum)
                            )
                            Text(day.highTemperature.shortTemperature)
                                .frame(width: 30, alignment: .trailing)
                        }
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: [
                        name,
                        day.condition.description,
                        String(localized: "High \(day.highTemperature.spokenTemperature)"),
                        String(localized: "Low \(day.lowTemperature.spokenTemperature)"),
                    ].joined(separator: ", ")))
                }
            }
        }
    }
}

/// A capsule track with the day's range filled in, cool blue to warm orange.
private struct TemperatureBar: View {
    /// 0...1 positions on the ten-day scale.
    let low: Double
    let high: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.35))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x5AC8FA), Color(hex: 0xFFD54F), Color(hex: 0xFF8A5C)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(width * (high - low), 6))
                    .offset(x: width * low)
            }
        }
        .frame(height: 5)
    }
}

/// The Apple Weather mark and data sources link that WeatherKit's terms require.
struct WatchAttributionView: View {
    @Environment(WeatherProvider.self) private var weather
    @Environment(\.skyMode) private var sky
    @State private var attribution: WeatherAttribution?

    var body: some View {
        VStack(spacing: 4) {
            if let attribution {
                AsyncImage(url: sky.isDark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather").font(.caption2)
                }
                .frame(height: 10)
                Link("Other data sources", destination: attribution.legalPageURL)
                    .font(.system(size: 10))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .readableOverEmoji()
        .task { attribution = await weather.attribution() }
    }
}

#if DEBUG
/// Sample hourly and 10-day forecasts for App Store screenshots, matching the scene's sample
/// temperatures, so every language shows the same weather.
extension WeatherScene {
    private static let fahrenheit = { (value: Double) in Measurement(value: value, unit: UnitTemperature.fahrenheit) }

    var sampleWatchHours: [WatchHour] {
        let start = ScreenshotMode.fixedDate ?? .now
        let isNight = ScreenshotMode.sky == .night || self == .clearNight
        // Small, natural swings around the current sample temperature.
        let offsets: [Double] = isNight
            ? [0, -1, -2, -2, -3, -4, -4, -5, -5, -4, -2, 0]
            : [0, 2, 3, 4, 4, 3, 2, 0, -2, -3, -4, -5]
        let rainy: Set<WeatherScene> = [.rain, .thunderstorm, .snow]
        return offsets.enumerated().map { index, offset in
            WatchHour(
                date: start.addingTimeInterval(Double(index) * 3600),
                condition: index < 6 ? sampleCondition : (rainy.contains(self) ? .cloudy : sampleCondition),
                isDaylight: !isNight && index < 9,
                temperature: Self.fahrenheit(sampleFahrenheit + offset),
                precipitationChance: rainy.contains(self) ? max(0, 0.8 - Double(index) * 0.07) : 0
            )
        }
    }

    var sampleWatchDays: [WatchDay] {
        let start = ScreenshotMode.fixedDate ?? .now
        let conditions: [WeatherCondition] = [sampleCondition, .partlyCloudy, .mostlyClear, .rain, .cloudy, .clear, .partlyCloudy, .thunderstorms, .mostlyClear, .clear]
        let highShift: [Double] = [0, 2, 4, -3, -5, 1, 3, -2, 0, 2]
        let chances: [Double] = [self == .rain || self == .thunderstorm || self == .snow ? 0.8 : 0, 0.1, 0, 0.6, 0.3, 0, 0.1, 0.5, 0, 0]
        return (0..<10).map { index in
            WatchDay(
                date: Calendar.current.date(byAdding: .day, value: index, to: start) ?? start,
                condition: index == 0 ? sampleCondition : (self == .snow && conditions[index] == .rain ? .snow : conditions[index]),
                lowTemperature: Self.fahrenheit(sampleLowFahrenheit + highShift[index] * 0.6),
                highTemperature: Self.fahrenheit(sampleHighFahrenheit + highShift[index]),
                precipitationChance: chances[index]
            )
        }
    }
}
#endif
