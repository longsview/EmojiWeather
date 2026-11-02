import SwiftUI
import WeatherKit

/// The Apple Weather mark and "Other data sources" link that WeatherKit's terms require.
struct WeatherAttributionView: View {
    @Environment(WeatherProvider.self) private var weather
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        VStack(spacing: 6) {
            if let attribution {
                // Apple's mark comes in a light and a dark version; match the sheet.
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather").font(.footnote)
                }
                .frame(height: 12)

                Link("Other data sources", destination: attribution.legalPageURL)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .task { attribution = await weather.attribution() }
    }
}
