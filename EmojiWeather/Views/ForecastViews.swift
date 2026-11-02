import SwiftUI
import WeatherKit

struct HourlyForecastView: View {
    let hours: [HourWeather]
    let timeZone: TimeZone

    var body: some View {
        ForecastCard(title: "Next 24 hours") {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        VStack(spacing: 8) {
                            Text(index == 0 ? "Now" : hour.date.formatted(Date.FormatStyle(timeZone: timeZone).hour()))
                                .font(.footnote.weight(.medium))
                            Text(WeatherScene.emoji(for: hour.condition, isDaylight: hour.isDaylight))
                                .font(.title2)
                            Text(hour.temperature.shortTemperature)
                                .font(.headline)
                        }
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

    var body: some View {
        ForecastCard(title: "10-day forecast") {
            VStack(spacing: 12) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    HStack {
                        Text(index == 0 ? "Today" : day.date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated)))
                            .frame(width: 60, alignment: .leading)
                        Text(WeatherScene.emoji(for: day.condition))
                            .font(.title3)
                            .frame(width: 40)
                        if day.precipitationChance >= 0.2 {
                            Text(day.precipitationChance.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)
                        }
                        Spacer()
                        Text(day.lowTemperature.shortTemperature)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(day.highTemperature.shortTemperature)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.body.weight(.medium))
                }
            }
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
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
    }
}
