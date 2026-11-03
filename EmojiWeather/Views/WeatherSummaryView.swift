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
        // The page is one screen tall, so cap the very largest sizes to keep it all visible.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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

/// The place's current time, so the pages double as a world clock. Cities in another time zone
/// also say how far ahead or behind they are.
struct LocalTimeView: View {
    let timeZone: TimeZone

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(context.date.formatted(DisplaySettings.timeStyle(timeZone)))
                    .monospacedDigit()
                if let offset = Self.offsetText(at: context.date, timeZone: timeZone) {
                    Text(offset)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .contentTransition(.numericText())
        }
        .accessibilityLabel("Local time")
    }

    /// "3 hr ahead", "5½ hr behind", or nil for the device's own time zone.
    static func offsetText(at date: Date, timeZone: TimeZone) -> String? {
        let difference = timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard difference != 0 else { return nil }
        let hours = Double(abs(difference)) / 3600
        let whole = Int(hours)
        let fraction = hours - Double(whole)
        let amount: String
        switch fraction {
        case 0: amount = whole.formatted()
        case 0.5: amount = whole == 0 ? "½" : "\(whole.formatted())½"
        default: amount = hours.formatted(.number.precision(.fractionLength(0...2)))
        }
        return difference > 0 ? String(localized: "\(amount) hr ahead") : String(localized: "\(amount) hr behind")
    }
}

extension View {
    /// Text color for the current sky, plus a soft halo that keeps text readable where it
    /// overlaps falling emoji.
    func readableOverEmoji() -> some View {
        modifier(ReadableOverEmoji())
    }
}

private struct ReadableOverEmoji: ViewModifier {
    @Environment(\.skyMode) private var sky

    func body(content: Content) -> some View {
        content
            .foregroundStyle(sky.textColor)
            .shadow(color: sky.haloColor, radius: 8)
            .shadow(color: sky.haloColor, radius: 8)
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
