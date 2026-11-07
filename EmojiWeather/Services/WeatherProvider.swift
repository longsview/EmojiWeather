import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Everything one screen needs, fetched in a single WeatherKit request.
struct WeatherSnapshot {
    let current: CurrentWeather
    let hourly: [HourWeather]
    let daily: [DayWeather]
    let fetchedAt: Date
}

/// Wraps WeatherKit with a 30-minute cache.
///
/// The developer membership includes 500,000 WeatherKit calls a month. One call returns current,
/// hourly and daily data together, so caching for 30 minutes keeps each user to a few calls a day.
@MainActor
@Observable
final class WeatherProvider {
    static let maxAge: TimeInterval = 30 * 60

    @ObservationIgnored private let service = WeatherService.shared
    @ObservationIgnored private var cache: [String: WeatherSnapshot] = [:]
    @ObservationIgnored private var cachedAttribution: WeatherAttribution?

    /// Returns cached weather for a location if it's fresh enough, without a network call.
    func cachedWeather(for location: CLLocation) -> WeatherSnapshot? {
        guard let snapshot = cache[Self.key(for: location)],
              Date.now.timeIntervalSince(snapshot.fetchedAt) < Self.maxAge else { return nil }
        return snapshot
    }

    func weather(for location: CLLocation, forceRefresh: Bool = false) async throws -> WeatherSnapshot {
        if !forceRefresh, let cached = cachedWeather(for: location) {
            return cached
        }

        let (current, hourly, daily) = try await service.weather(
            for: location,
            including: .current, .hourly, .daily
        )
        let startOfHour = Date.now.addingTimeInterval(-3_600)
        let snapshot = WeatherSnapshot(
            current: current,
            hourly: Array(hourly.forecast.filter { $0.date >= startOfHour }.prefix(24)),
            daily: Array(daily.forecast.prefix(10)),
            fetchedAt: .now
        )
        cache[Self.key(for: location)] = snapshot
        return snapshot
    }

    /// The Apple Weather mark and legal link that WeatherKit's terms require the app to show.
    func attribution() async -> WeatherAttribution? {
        if let cachedAttribution { return cachedAttribution }
        cachedAttribution = try? await service.attribution
        return cachedAttribution
    }

    /// Rounds to about 1 km so small GPS changes reuse the same cache entry.
    private static func key(for location: CLLocation) -> String {
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }
}
