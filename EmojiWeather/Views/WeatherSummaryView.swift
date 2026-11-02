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
    let temperature: String
    let condition: String
    var high: String?
    var low: String?
    let tagline: String

    var body: some View {
        VStack(spacing: 4) {
            PlaceNameRow(placeName: placeName, showsLocationIcon: showsLocationIcon)

            Text(temperature)
                .font(.system(size: 112, weight: .heavy, design: .rounded))
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
