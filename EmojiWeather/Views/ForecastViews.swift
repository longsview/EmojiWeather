import SwiftUI
import WeatherKit

/// The forecast sheet and share card's text, already formatted. Built from WeatherKit, or in
/// screenshot mode from sample numbers that match the forced scene.
struct ForecastContent {
    struct Hour: Hashable {
        let time: String
        let emoji: String
        let temperature: String
        let spoken: String
    }

    struct Day: Hashable {
        let name: String
        let emoji: String
        /// "40%", only when rain is likely enough to mention.
        let chance: String?
        let low: String
        let high: String
        let spoken: String
    }

    struct Tile: Identifiable, Hashable {
        let emoji: String
        let title: String
        let value: String
        var id: String { title }
    }

    let temperature: String
    let condition: String
    let high: String?
    let low: String?
    let hours: [Hour]
    let days: [Day]
    let tiles: [Tile]
    /// "Good to know": weather worth a precaution, most important first.
    var notes: [Note] = []

    struct Note: Identifiable, Hashable {
        let emoji: String
        let title: String
        let advice: String
        var id: String { title }
    }
}

extension ForecastContent {
    init(snapshot: WeatherSnapshot, timeZone: TimeZone) {
        let current = snapshot.current
        let today = snapshot.daily.first
        temperature = current.temperature.shortTemperature
        condition = current.condition.description
        high = today?.highTemperature.shortTemperature
        low = today?.lowTemperature.shortTemperature

        hours = snapshot.hourly.enumerated().map { index, hour in
            let time = index == 0 ? String(localized: "Now") : hour.date.formatted(DisplaySettings.hourStyle(timeZone))
            return Hour(
                time: time,
                emoji: WeatherScene.emoji(for: hour.condition, isDaylight: hour.isDaylight),
                temperature: hour.temperature.shortTemperature,
                // Read like Apple Weather: "3 PM, Sunny, 72 degrees".
                spoken: "\(time), \(hour.condition.description), \(hour.temperature.spokenTemperature)"
            )
        }

        days = snapshot.daily.enumerated().map { index, day in
            let name = index == 0 ? String(localized: "Today") : day.date.formatted(DisplaySettings.weekdayStyle(timeZone))
            let chance = day.precipitationChance >= 0.2
                ? day.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
                : nil
            return Day(
                name: name,
                emoji: WeatherScene.emoji(for: day.condition),
                chance: chance,
                low: day.lowTemperature.shortTemperature,
                high: day.highTemperature.shortTemperature,
                spoken: Self.spokenDay(
                    name: name, condition: day.condition.description,
                    high: day.highTemperature.spokenTemperature, low: day.lowTemperature.spokenTemperature,
                    chance: chance
                )
            )
        }

        let measurement = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let windSpeed = current.wind.speed.formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: measurement))
        var tiles = [
            Tile(emoji: "🌡️", title: String(localized: "Feels like"), value: current.apparentTemperature.shortTemperature),
            Tile(emoji: "💦", title: String(localized: "Humidity"), value: current.humidity.formatted(.percent.precision(.fractionLength(0)))),
            Tile(emoji: "🌬️", title: String(localized: "Wind"), value: windSpeed + " " + current.wind.compassDirection.abbreviation),
            Tile(emoji: "🕶️", title: String(localized: "UV index"), value: "\(current.uvIndex.value) \(current.uvIndex.category.description)"),
            Tile(
                emoji: "👀", title: String(localized: "Visibility"),
                value: current.visibility.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: measurement))
            ),
            Tile(emoji: "⏲️", title: String(localized: "Pressure"), value: Self.pressure(current.pressure, trend: current.pressureTrend)),
            Tile(emoji: "💧", title: String(localized: "Dew point"), value: current.dewPoint.shortTemperature),
        ]
        if let today {
            tiles.append(Tile(emoji: "☔️", title: String(localized: "Rain chance"), value: today.precipitationChance.formatted(.percent.precision(.fractionLength(0)))))
            let timeStyle = DisplaySettings.timeStyle(timeZone)
            if let sunrise = today.sun.sunrise {
                tiles.append(Tile(emoji: "🌅", title: String(localized: "Sunrise"), value: sunrise.formatted(timeStyle)))
            }
            if let sunset = today.sun.sunset {
                tiles.append(Tile(emoji: "🌇", title: String(localized: "Sunset"), value: sunset.formatted(timeStyle)))
            }
        }
        self.tiles = tiles
        notes = Self.notes(current: current, today: today, hourly: snapshot.hourly)
    }

    /// Precautions for today's weather, at most four, most important first. General tips, written
    /// as information rather than health predictions.
    static func notes(current: CurrentWeather, today: DayWeather?, hourly: [HourWeather]) -> [Note] {
        var notes: [Note] = []
        let feelsLike = current.apparentTemperature.converted(to: .celsius).value
        let feelsLikeText = current.apparentTemperature.shortTemperature

        if feelsLike >= 32 {
            notes.append(Note(
                emoji: "🥵", title: String(localized: "Feels like \(feelsLikeText)"),
                advice: String(localized: "Drink water, take breaks in the shade and check on people who feel the heat more.")
            ))
        } else if feelsLike <= -10 {
            notes.append(Note(
                emoji: "🥶", title: String(localized: "Feels like \(feelsLikeText)"),
                advice: String(localized: "Cover exposed skin and keep time outside short. Frostbite can start quickly in the wind.")
            ))
        }

        let uv = max(current.uvIndex.value, today?.uvIndex.value ?? 0)
        if uv >= 6 {
            let uvText = "\(uv)"
            notes.append(Note(
                emoji: "🧴", title: uv >= 8 ? String(localized: "Very high UV (\(uvText))") : String(localized: "High UV (\(uvText))"),
                advice: String(localized: "Sunscreen, sunglasses and a hat, and shade around midday when the sun is strongest.")
            ))
        }

        // Pressure over the next 12 hours: a quick fall usually comes ahead of a storm.
        if let first = hourly.first, hourly.count >= 13 {
            let change = hourly[12].pressure.converted(to: .hectopascals).value - first.pressure.converted(to: .hectopascals).value
            if change <= -5 {
                let amount = Self.pressureChange(Measurement(value: -change, unit: UnitPressure.hectopascals))
                notes.append(Note(
                    emoji: "📉", title: String(localized: "Pressure dropping"),
                    advice: String(localized: "Down \(amount) over the next 12 hours, often ahead of a storm. Some people notice headaches or achy joints when pressure falls quickly.")
                ))
            }
        }

        if let gust = current.wind.gust, gust.converted(to: .kilometersPerHour).value >= 60 {
            let gustText = gust.formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
            notes.append(Note(
                emoji: "💨", title: String(localized: "Gusts up to \(gustText)"),
                advice: String(localized: "Secure loose things outside and watch for falling branches.")
            ))
        }

        if current.visibility.converted(to: .meters).value < 1_000 {
            notes.append(Note(
                emoji: "🌫️", title: String(localized: "Low visibility"),
                advice: String(localized: "If you're driving, slow down, leave extra space and use low beams.")
            ))
        }

        if let today, today.precipitationChance >= 0.6 {
            let chance = today.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
            notes.append(Note(
                emoji: "☔️", title: String(localized: "Rain likely (\(chance))"),
                advice: String(localized: "Bring an umbrella, and give yourself extra time on wet roads.")
            ))
        }

        if current.dewPoint.converted(to: .celsius).value >= 21 {
            let dewText = current.dewPoint.shortTemperature
            notes.append(Note(
                emoji: "💦", title: String(localized: "Muggy air"),
                advice: String(localized: "Dew point \(dewText). Sweat dries slowly, so heat feels harder on the body. Pace yourself.")
            ))
        }

        return Array(notes.prefix(4))
    }

    /// "0.21 inHg" in the US, "7 hPa" elsewhere.
    static func pressureChange(_ value: Measurement<UnitPressure>) -> String {
        let usesInches = DisplaySettings.locale.measurementSystem == .us
        let unit: UnitPressure = usesInches ? .inchesOfMercury : .hectopascals
        let number = value.converted(to: unit).value
            .formatted(.number.precision(.fractionLength(usesInches ? 2 : 0)).locale(DisplaySettings.locale))
        return "\(number) \(usesInches ? "inHg" : "hPa")"
    }

    /// "30.02 inHg ↑" in the US, "1017 hPa ↓" elsewhere, with which way it's heading.
    static func pressure(_ value: Measurement<UnitPressure>, trend: PressureTrend) -> String {
        let usesInches = DisplaySettings.locale.measurementSystem == .us
        let unit: UnitPressure = usesInches ? .inchesOfMercury : .hectopascals
        let number = value.converted(to: unit).value
            .formatted(.number.precision(.fractionLength(usesInches ? 2 : 0)).locale(DisplaySettings.locale))
        let arrow = switch trend {
        case .rising: " ↑"
        case .falling: " ↓"
        default: ""
        }
        return "\(number) \(usesInches ? "inHg" : "hPa")\(arrow)"
    }

    fileprivate static func spokenDay(name: String, condition: String, high: String, low: String, chance: String?) -> String {
        var parts = [
            name,
            condition,
            String(localized: "High \(high)"),
            String(localized: "Low \(low)"),
        ]
        if let chance {
            parts.append(String(localized: "\(chance) chance of rain"))
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
extension ForecastContent {
    /// Screenshot mode: a believable forecast for the forced scene, starting at the fixed clock time.
    static func sample(for scene: WeatherScene, sky: SkyMode, timeZone: TimeZone) -> ForecastContent {
        let start = ScreenshotMode.fixedDate ?? .now
        let base = Self.number(scene.sampleTemperature)
        let high = max(Self.number(scene.sampleHigh), base)
        let low = min(Self.number(scene.sampleLow), base)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Warmest mid-afternoon, coolest just before dawn, pinned so "Now" is the sample temperature.
        func warmth(_ hour: Int) -> Double { (cos(Double(hour - 15) / 24 * 2 * .pi) + 1) / 2 }
        let startHour = calendar.component(.hour, from: start)
        let condition = scene.sampleCondition
        let isWet = ([.rain, .thunderstorm, .snow] as [WeatherScene]).contains(scene)

        let hours: [Hour] = (0..<24).map { index in
            let date = start.addingTimeInterval(Double(index) * 3_600)
            let hour = calendar.component(.hour, from: date)
            let raw = Double(base) + (warmth(hour) - warmth(startHour)) * Double(high - low)
            let temperature = "\(Int(min(Double(high), max(Double(low), raw)).rounded()))°"
            // Wet weather clears up later on; other scenes keep their sky.
            let hourCondition: WeatherCondition = isWet && index >= 7 ? .mostlyCloudy : condition
            let time = index == 0 ? String(localized: "Now") : date.formatted(DisplaySettings.hourStyle(timeZone))
            return Hour(
                time: time,
                emoji: WeatherScene.emoji(for: hourCondition, isDaylight: (7..<18).contains(hour)),
                temperature: temperature,
                spoken: "\(time), \(hourCondition.description), \(temperature)"
            )
        }

        let pattern: [WeatherCondition] = [condition, .partlyCloudy, .clear, .clear, .mostlyCloudy, .rain, .partlyCloudy, .clear, .mostlyClear, .partlyCloudy]
        let swings = [0, 2, 3, 1, -2, -4, -1, 2, 3, 1]
        let days: [Day] = pattern.enumerated().map { index, dayCondition in
            let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
            let name = index == 0 ? String(localized: "Today") : date.formatted(DisplaySettings.weekdayStyle(timeZone))
            let chance: String? = switch dayCondition {
            case .rain, .snow: "60%"
            case .thunderstorms: "80%"
            default: nil
            }
            let dayHigh = "\(high + swings[index])°"
            let dayLow = "\(low + swings[index] / 2)°"
            return Day(
                name: name, emoji: WeatherScene.emoji(for: dayCondition), chance: chance, low: dayLow, high: dayHigh,
                spoken: Self.spokenDay(name: name, condition: dayCondition.description, high: dayHigh, low: dayLow, chance: chance)
            )
        }

        let timeStyle = DisplaySettings.timeStyle(timeZone)
        let sunrise = calendar.date(bySettingHour: 6, minute: 42, second: 0, of: start) ?? start
        let sunset = calendar.date(bySettingHour: 17, minute: 3, second: 0, of: start) ?? start
        let isDaytime = sky != .night
        let tiles = [
            Tile(emoji: "🌡️", title: String(localized: "Feels like"), value: "\(base + (scene == .snow ? -5 : 2))°"),
            Tile(emoji: "💦", title: String(localized: "Humidity"), value: "\(scene.sampleHumidity)%"),
            Tile(emoji: "🌬️", title: String(localized: "Wind"), value: scene == .windy ? "24 mph W" : "6 mph W"),
            Tile(emoji: "🕶️", title: String(localized: "UV index"), value: isDaytime && scene.showsSunOrMoon ? "6 High" : "1 Low"),
            Tile(emoji: "👀", title: String(localized: "Visibility"), value: scene == .foggy ? "0.5 mi" : "10 mi"),
            Tile(emoji: "⏲️", title: String(localized: "Pressure"), value: [.rain, .thunderstorm, .snow].contains(scene) ? "29.71 inHg ↓" : "30.02 inHg ↑"),
            Tile(emoji: "💧", title: String(localized: "Dew point"), value: "\(base - (scene == .hot ? 40 : 14))°"),
            Tile(emoji: "☔️", title: String(localized: "Rain chance"), value: days[0].chance ?? "0%"),
            Tile(emoji: "🌅", title: String(localized: "Sunrise"), value: sunrise.formatted(timeStyle)),
            Tile(emoji: "🌇", title: String(localized: "Sunset"), value: sunset.formatted(timeStyle)),
        ]

        return ForecastContent(
            temperature: scene.sampleTemperature, condition: scene.title,
            high: scene.sampleHigh, low: scene.sampleLow,
            hours: hours, days: days, tiles: tiles,
            notes: Self.sampleNotes(for: scene, sky: sky)
        )
    }

    /// Screenshot mode: the notes that scene would bring.
    static func sampleNotes(for scene: WeatherScene, sky: SkyMode) -> [Note] {
        switch scene {
        case .sunny, .hot, .partlyCloudy:
            guard sky != .night else { return [] }
            return [Note(
                emoji: "🧴", title: String(localized: "High UV (\("7"))"),
                advice: String(localized: "Sunscreen, sunglasses and a hat, and shade around midday when the sun is strongest.")
            )]
        case .thunderstorm, .rain:
            return [
                Note(emoji: "☔️", title: String(localized: "Rain likely (\("80%"))"),
                     advice: String(localized: "Bring an umbrella, and give yourself extra time on wet roads.")),
                Note(emoji: "📉", title: String(localized: "Pressure dropping"),
                     advice: String(localized: "Down \("0.21 inHg") over the next 12 hours, often ahead of a storm. Some people notice headaches or achy joints when pressure falls quickly.")),
            ]
        default:
            return []
        }
    }

    /// 75 from "75°".
    private static func number(_ text: String) -> Int {
        Int(text.filter { $0.isNumber || $0 == "-" }) ?? 0
    }
}

extension WeatherScene {
    fileprivate var sampleCondition: WeatherCondition {
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

    fileprivate var sampleHumidity: Int {
        switch self {
        case .rain, .thunderstorm, .foggy: 88
        case .snow: 79
        case .hot: 18
        case .sunny, .windy: 34
        default: 56
        }
    }
}
#endif

/// "Good to know": short precautions for today's weather.
struct WeatherNotesView: View {
    let notes: [ForecastContent.Note]

    var body: some View {
        ForecastCard(title: String(localized: "Good to know")) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(notes) { note in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: note.emoji)
                            .font(.title2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: note.title)
                                .font(.system(.headline, design: .rounded))
                            Text(verbatim: note.advice)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("General tips, not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct HourlyForecastView: View {
    let hours: [ForecastContent.Hour]

    var body: some View {
        ForecastCard(title: String(localized: "Next 24 hours")) {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 8) {
                            Text(verbatim: hour.time)
                                .font(.footnote.weight(.medium))
                            Text(verbatim: hour.emoji)
                                .font(.title2)
                                .accessibilityHidden(true)
                            Text(verbatim: hour.temperature)
                                .font(.headline)
                        }
                        // One VoiceOver stop per hour.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: hour.spoken))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct DailyForecastView: View {
    let days: [ForecastContent.Day]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ForecastCard(title: String(localized: "10-day forecast")) {
            VStack(spacing: 12) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    row(day: day)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: day.spoken))
                }
            }
        }
    }

    @ViewBuilder
    private func row(day: ForecastContent.Day) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Large text: stack the row so nothing gets squeezed or cut off.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: day.name)
                    Spacer()
                    Text(verbatim: day.emoji)
                }
                HStack {
                    if let chance = day.chance {
                        Text(verbatim: chance).foregroundStyle(.cyan)
                    }
                    Spacer()
                    Text(verbatim: day.low).foregroundStyle(.secondary)
                    Text(verbatim: day.high)
                }
            }
            .font(.body.weight(.medium))
        } else {
            HStack {
                Text(verbatim: day.name)
                    .frame(minWidth: 60, alignment: .leading)
                Text(verbatim: day.emoji)
                    .font(.title3)
                    .frame(width: 40)
                if let chance = day.chance {
                    Text(verbatim: chance)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Spacer()
                Text(verbatim: day.low)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
                Text(verbatim: day.high)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .font(.body.weight(.medium))
        }
    }
}

struct ForecastCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}
