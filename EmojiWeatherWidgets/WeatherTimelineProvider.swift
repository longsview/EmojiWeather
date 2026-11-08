import CoreLocation
import WeatherKit
import WidgetKit

struct WeatherEntry: TimelineEntry {
    let date: Date
    let place: WidgetPlace?
    let weather: WidgetWeather?
    /// Skymoji+ (or any Debug build).
    let isUnlocked: Bool
    /// True when the widget steps through all places, so it shows the arrow.
    let isCycling: Bool
    let placeCount: Int

    func at(_ date: Date) -> WeatherEntry {
        WeatherEntry(date: date, place: place, weather: weather, isUnlocked: isUnlocked, isCycling: isCycling, placeCount: placeCount)
    }

    static let sample = WeatherEntry(
        date: .now,
        place: WidgetPlace(id: "sample", name: "Cupertino", latitude: 37.32, longitude: -122.03),
        weather: WidgetWeather(
            temperature: .init(value: 21, unit: .celsius),
            high: .init(value: 24, unit: .celsius),
            low: .init(value: 13, unit: .celsius),
            condition: "Mostly Sunny",
            scene: .sunny,
            sky: .day,
            hours: (1...5).map {
                .init(date: .now.addingTimeInterval(Double($0) * 3600), temperature: .init(value: 21 + Double($0 % 3), unit: .celsius), emoji: $0 < 4 ? "☀️" : "🌤️")
            },
            days: ["☀️", "🌤️", "🌧️", "⛈️", "☀️"].enumerated().map { index, emoji in
                .init(date: .now.addingTimeInterval(Double(index) * 86_400), high: .init(value: 24 - Double(index), unit: .celsius), low: .init(value: 13, unit: .celsius), emoji: emoji)
            },
            fetchedAt: .now
        ),
        isUnlocked: true,
        isCycling: true,
        placeCount: 3
    )
}

struct WeatherTimelineProvider: AppIntentTimelineProvider {
    /// Weather the app saved is reused for this long before the widget fetches its own.
    private static let maxAge: TimeInterval = 45 * 60

    func placeholder(in context: Context) -> WeatherEntry { .sample }

    func snapshot(for configuration: SelectPlaceIntent, in context: Context) async -> WeatherEntry {
        if context.isPreview { return .sample }
        return await entry(for: configuration, allowFetch: false)
    }

    func timeline(for configuration: SelectPlaceIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let first = await entry(for: configuration, allowFetch: true)
        // One entry a minute for the next half hour keeps the local time current.
        let calendar = Calendar.current
        let startOfMinute = calendar.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = [first] + (1...30).map { minute in
            first.at(startOfMinute.addingTimeInterval(Double(minute) * 60))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for configuration: SelectPlaceIntent, allowFetch: Bool) async -> WeatherEntry {
        // Plus only, in Debug too, so builds behave the same as the App Store.
        let isUnlocked = SharedStore.hasPlus

        let places = SharedStore.places
        let pinned = configuration.place.flatMap { pinned in places.first { $0.id == pinned.id } }
        let place: WidgetPlace? = pinned ?? (places.isEmpty ? nil : places[((SharedStore.cycleIndex % places.count) + places.count) % places.count])

        var weather = place.flatMap { SharedStore.weather(for: $0.id) }
        if allowFetch, isUnlocked, let place,
           weather.map({ Date.now.timeIntervalSince($0.fetchedAt) > Self.maxAge }) ?? true,
           let fresh = await fetch(place) {
            weather = fresh
            SharedStore.setWeather(fresh, for: place.id)
        }

        return WeatherEntry(
            date: .now,
            place: place,
            weather: weather,
            isUnlocked: isUnlocked,
            isCycling: pinned == nil && places.count > 1,
            placeCount: places.count
        )
    }

    private func fetch(_ place: WidgetPlace) async -> WidgetWeather? {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let (current, hourly, daily) = try? await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly, .daily
        ) else { return nil }
        return WidgetWeather(
            current: current,
            hourly: Array(hourly.forecast.prefix(12)),
            daily: Array(daily.forecast.prefix(5)),
            fetchedAt: .now
        )
    }
}
