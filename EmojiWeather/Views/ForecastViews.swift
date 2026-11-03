import SwiftUI
import WeatherKit

struct HourlyForecastView: View {
    let hours: [HourWeather]
    let timeZone: TimeZone

    var body: some View {
        ForecastCard(title: String(localized: "Next 24 hours")) {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        let time = index == 0 ? String(localized: "Now") : hour.date.formatted(DisplaySettings.hourStyle(timeZone))
                        VStack(spacing: 8) {
                            Text(time)
                                .font(.footnote.weight(.medium))
                            Text(WeatherScene.emoji(for: hour.condition, isDaylight: hour.isDaylight))
                                .font(.title2)
                                .accessibilityHidden(true)
                            Text(hour.temperature.shortTemperature)
                                .font(.headline)
                        }
                        // One VoiceOver stop per hour, read like Apple Weather: "3 PM, Sunny, 72 degrees".
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(time), \(hour.condition.description), \(hour.temperature.spokenTemperature)"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct DailyForecastView: View {
    let days: [DayWeather]
    let timeZone: TimeZone

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ForecastCard(title: String(localized: "10-day forecast")) {
            VStack(spacing: 12) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let name = index == 0 ? String(localized: "Today") : day.date.formatted(DisplaySettings.weekdayStyle(timeZone))
                    row(day: day, name: name)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(day: day, name: name))
                }
            }
        }
    }

    @ViewBuilder
    private func row(day: DayWeather, name: String) -> some View {
        let chance = day.precipitationChance >= 0.2
            ? day.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
            : nil
        if dynamicTypeSize.isAccessibilitySize {
            // Large text: stack the row so nothing gets squeezed or cut off.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                    Spacer()
                    Text(WeatherScene.emoji(for: day.condition))
                }
                HStack {
                    if let chance {
                        Text(chance).foregroundStyle(.cyan)
                    }
                    Spacer()
                    Text(day.lowTemperature.shortTemperature).foregroundStyle(.secondary)
                    Text(day.highTemperature.shortTemperature)
                }
            }
            .font(.body.weight(.medium))
        } else {
            HStack {
                Text(name)
                    .frame(minWidth: 60, alignment: .leading)
                Text(WeatherScene.emoji(for: day.condition))
                    .font(.title3)
                    .frame(width: 40)
                if let chance {
                    Text(chance)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Spacer()
                Text(day.lowTemperature.shortTemperature)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
                Text(day.highTemperature.shortTemperature)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .font(.body.weight(.medium))
        }
    }

    private func accessibilityText(day: DayWeather, name: String) -> String {
        var parts = [
            name,
            day.condition.description,
            String(localized: "High \(day.highTemperature.spokenTemperature)"),
            String(localized: "Low \(day.lowTemperature.spokenTemperature)"),
        ]
        if day.precipitationChance >= 0.2 {
            let chance = day.precipitationChance.formatted(.percent.precision(.fractionLength(0)))
            parts.append(String(localized: "\(chance) chance of rain"))
        }
        return parts.joined(separator: ", ")
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
