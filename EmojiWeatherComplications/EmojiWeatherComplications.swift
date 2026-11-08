import CoreLocation
import SwiftUI
import WeatherKit
import WidgetKit

@main
struct EmojiWeatherComplications: WidgetBundle {
    var body: some Widget {
        EmojiWeatherComplication()
    }
}

/// Watch face complications: the weather where you are (or your first city) as emoji.
struct EmojiWeatherComplication: Widget {
    let kind = "EmojiWeatherComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Skymoji")
        .description("Your weather as emoji.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let place: WidgetPlace?
    let weather: WidgetWeather?

    static let sample = ComplicationEntry(
        date: .now,
        place: WidgetPlace(id: "sample", name: "Cupertino", latitude: 37.32, longitude: -122.03),
        weather: WidgetWeather(
            temperature: .init(value: 21, unit: .celsius),
            high: .init(value: 24, unit: .celsius),
            low: .init(value: 13, unit: .celsius),
            condition: "Mostly Sunny",
            scene: .sunny,
            sky: .day,
            hours: [],
            fetchedAt: .now
        )
    )
}

/// Reads the place and weather the watch app saved to the App Group, and fetches its own
/// weather from WeatherKit when that's more than 45 minutes old.
struct ComplicationProvider: TimelineProvider {
    private static let maxAge: TimeInterval = 45 * 60

    func placeholder(in context: Context) -> ComplicationEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        Task { completion(await entry(allowFetch: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        Task {
            let entry = await entry(allowFetch: true)
            // Complications have a small refresh budget; every 30 minutes is plenty for weather.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    private func entry(allowFetch: Bool) async -> ComplicationEntry {
        // My Location when the watch app has a fix, otherwise the first saved city.
        guard let place = SharedStore.places.first else {
            return ComplicationEntry(date: .now, place: nil, weather: nil)
        }
        var weather = SharedStore.weather(for: place.id)
        if allowFetch,
           weather.map({ Date.now.timeIntervalSince($0.fetchedAt) > Self.maxAge }) ?? true,
           let fresh = await fetch(place) {
            weather = fresh
            SharedStore.setWeather(fresh, for: place.id)
        }
        return ComplicationEntry(date: .now, place: place, weather: weather)
    }

    private func fetch(_ place: WidgetPlace) async -> WidgetWeather? {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let (current, hourly, daily) = try? await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly, .daily
        ) else { return nil }
        return WidgetWeather(
            current: current,
            hourly: Array(hourly.forecast.prefix(6)),
            daily: Array(daily.forecast.prefix(2)),
            fetchedAt: .now
        )
    }
}
