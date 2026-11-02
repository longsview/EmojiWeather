import SwiftUI
import WeatherKit

/// The "swipe up" page: hourly and 10-day forecasts plus current conditions.
struct DetailsView: View {
    let placeName: String
    let snapshot: WeatherSnapshot
    let timeZone: TimeZone
    var refresh: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(placeName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .padding(.top, 8)

                HourlyForecastView(hours: snapshot.hourly, timeZone: timeZone)
                ForecastAdCard()
                ConditionsGrid(current: snapshot.current, today: snapshot.daily.first, timeZone: timeZone)
                DailyForecastView(days: snapshot.daily, timeZone: timeZone)

                WeatherAttributionView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding()
        }
        .refreshable { await refresh() }
        .foregroundStyle(.black)
    }
}

/// Tiles for the conditions people check most, each with its own emoji.
private struct ConditionsGrid: View {
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
        var tiles = [
            Tile(emoji: "🌡️", title: "Feels like", value: current.apparentTemperature.shortTemperature),
            Tile(emoji: "💦", title: "Humidity", value: current.humidity.formatted(.percent.precision(.fractionLength(0)))),
            Tile(
                emoji: "🌬️", title: "Wind",
                value: current.wind.speed.formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))))
                    + " " + current.wind.compassDirection.abbreviation
            ),
            Tile(emoji: "🕶️", title: "UV index", value: "\(current.uvIndex.value) \(current.uvIndex.category.description)"),
            Tile(
                emoji: "👀", title: "Visibility",
                value: current.visibility.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
            ),
        ]
        if let today {
            tiles.append(Tile(emoji: "☔️", title: "Rain chance", value: today.precipitationChance.formatted(.percent.precision(.fractionLength(0)))))
            let timeStyle = Date.FormatStyle(timeZone: timeZone).hour().minute()
            if let sunrise = today.sun.sunrise {
                tiles.append(Tile(emoji: "🌅", title: "Sunrise", value: sunrise.formatted(timeStyle)))
            }
            if let sunset = today.sun.sunset {
                tiles.append(Tile(emoji: "🌇", title: "Sunset", value: sunset.formatted(timeStyle)))
            }
        }
        return tiles
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: 6) {
                    Text(tile.emoji).font(.title)
                    Text(tile.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(tile.value)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.black.opacity(0.045), in: .rect(cornerRadius: 24))
            }
        }
    }
}
