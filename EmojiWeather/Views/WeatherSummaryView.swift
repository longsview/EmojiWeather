import SwiftUI

/// The city name row, shown on its own while weather is loading.
struct PlaceNameRow: View {
    let placeName: String
    var showsLocationIcon = false

    var body: some View {
        HStack(spacing: 6) {
            if showsLocationIcon {
                Image(systemName: "location.fill").font(.subheadline)
            }
            Text(placeName)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.system(.title2, design: .rounded, weight: .bold))
    }
}

/// The first page's text: city, big temperature, condition, high/low and a short line.
/// Shared by the city pages and the debug scene gallery so both look the same.
struct WeatherSummaryView: View {
    let placeName: String
    var showsLocationIcon = false
    /// The place's time zone, for the local-time line above the temperature.
    var timeZone: TimeZone = .current
    let temperature: String
    let condition: String
    var high: String?
    var low: String?
    let tagline: String
    /// What VoiceOver reads for the whole block, e.g. "68 degrees, Cloudy, High 72 degrees,
    /// Low 55 degrees". Uses the visible text when nil.
    var spokenWeather: String?

    /// The big temperature grows and shrinks with the text size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 112

    var body: some View {
        VStack(spacing: 4) {
            PlaceNameRow(placeName: placeName, showsLocationIcon: showsLocationIcon)

            LocalTimeView(timeZone: timeZone)
                .padding(.top, 2)

            Text(temperature)
                .font(.system(size: temperatureSize, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.vertical, -10)

            Text(condition)
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let high, let low {
                HStack(spacing: 14) {
                    Label(high, systemImage: "arrow.up")
                    Label(low, systemImage: "arrow.down")
                }
                .font(.system(.headline, design: .rounded))
                .labelStyle(TightLabelStyle())
            }

            Text(tagline)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .readableOverEmoji()
        // The page is one screen tall, so like Apple Weather it stops growing at the largest
        // standard size. The forecast sheet scrolls and takes every size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // VoiceOver: one stop for the place name (a heading) and one for the weather, like
        // Apple Weather.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let time = Date.now.formatted(DisplaySettings.timeStyle(timeZone))
        var parts = [placeName, time, spokenWeather ?? "\(temperature), \(condition)"]
        if spokenWeather == nil, let high, let low {
            parts.append(String(localized: "High \(high)"))
            parts.append(String(localized: "Low \(low)"))
        }
        parts.append(tagline)
        return parts.joined(separator: ", ")
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.caption.weight(.heavy))
            configuration.title
        }
    }
}
