import SwiftUI
import WidgetKit

@main
struct EmojiWeatherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EmojiWeatherWidget()
    }
}

/// One widget in every size: Lock Screen (circular, rectangular, inline) and Home Screen
/// (small, medium). Each shows a chosen place, or steps through all places with the arrow.
struct EmojiWeatherWidget: Widget {
    let kind = "EmojiWeatherWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectPlaceIntent.self, provider: WeatherTimelineProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("EmojiWeather")
        .description("Your weather as emoji. Tap the arrow to step through your places.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
            .systemSmall, .systemMedium, .systemLarge,
        ])
        .contentMarginsDisabled()
    }
}
