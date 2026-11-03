import SwiftUI

/// The "swipe up" page: hourly and 10-day forecasts plus current conditions.
struct DetailsView: View {
    let placeName: String
    let forecast: ForecastContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(placeName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                HourlyForecastView(hours: forecast.hours)
                ForecastAdCard()
                ConditionsGrid(tiles: forecast.tiles)
                DailyForecastView(days: forecast.days)

                WeatherAttributionView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding()
        }
    }
}

/// Tiles for the conditions people check most, each with its own emoji.
private struct ConditionsGrid: View {
    let tiles: [ForecastContent.Tile]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // One column at the largest text sizes so values don't shrink or truncate.
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 12) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: tile.emoji).font(.title).accessibilityHidden(true)
                    Text(tile.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(verbatim: tile.value)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 24))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
