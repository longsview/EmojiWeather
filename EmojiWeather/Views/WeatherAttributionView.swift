import SwiftUI
import WeatherKit

/// The Apple Weather mark and "Other data sources" link that WeatherKit's terms require.
struct WeatherAttributionView: View {
    @Environment(WeatherProvider.self) private var weather
    @State private var attribution: WeatherAttribution?

    var body: some View {
        VStack(spacing: 6) {
            if let attribution {
                // The scene behind is dark-ish, so use the mark made for dark backgrounds.
                AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather").font(.footnote)
                }
                .frame(height: 12)

                Link("Other data sources", destination: attribution.legalPageURL)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .task { attribution = await weather.attribution() }
    }
}
