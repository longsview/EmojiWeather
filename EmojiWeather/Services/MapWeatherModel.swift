import CoreLocation
import MapKit
import Observation
import os
import WeatherKit

/// Weather for the emoji map, shown on real cities and towns like the old TV maps.
/// For the visible area it picks the biggest places that aren't crowded together, then gets
/// one current-weather call per place, cached for 30 minutes.
@MainActor
@Observable
final class MapWeatherModel {
    struct Marker: Identifiable, Equatable {
        /// Row in the cities list.
        let id: Int
        let name: String
        let coordinate: CLLocationCoordinate2D
        let emoji: String
        let condition: String
        let temperature: Measurement<UnitTemperature>

        static func == (lhs: Marker, rhs: Marker) -> Bool {
            lhs.id == rhs.id && lhs.emoji == rhs.emoji && lhs.temperature == rhs.temperature
        }
    }

    private struct CachedMarker {
        let marker: Marker
        let fetchedAt: Date
    }

    /// At most this many places on screen.
    private static let maxPlaces = 14
    /// Places closer than this share of the screen's short side are skipped.
    private static let minSpacing = 0.24
    private static let maxAge: TimeInterval = 30 * 60
    private static let maxConcurrentRequests = 6

    private(set) var markers: [Marker] = []
    private(set) var isLoading = false

    @ObservationIgnored private var cache: [Int: CachedMarker] = [:]
    @ObservationIgnored private var inFlight: Set<Int> = []
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var cities: CityIndex?

    /// Call when the map stops moving.
    func update(region: MKCoordinateRegion) {
        updateTask?.cancel()
        updateTask = Task {
            // Wait for the map to settle so a long pan is one batch of calls, not many.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if cities == nil { cities = await CityIndex.load() }
            guard let cities, !Task.isCancelled else { return }
            // Picking from 60,000 cities is too slow for the main thread, especially in Debug.
            let maxPlaces = Self.maxPlaces
            let spacing = Self.minSpacing
            let places = await Task.detached(priority: .userInitiated) {
                cities.places(in: region, max: maxPlaces, spacing: spacing)
            }.value
            guard !Task.isCancelled else { return }
            await load(places: places)
        }
    }

    private func load(places: [CityIndex.Place]) async {
        let ids = places.map(\.id)
        show(ids)

        let now = Date.now
        let missing = places.filter { place in
            guard !inFlight.contains(place.id) else { return false }
            guard let cached = cache[place.id] else { return true }
            return now.timeIntervalSince(cached.fetchedAt) > Self.maxAge
        }
        guard !missing.isEmpty else { return }

        isLoading = true
        inFlight.formUnion(missing.map(\.id))

        await withTaskGroup(of: (Int, Marker?).self) { group in
            var pending = missing.makeIterator()
            // A few requests at a time; each finished one starts the next.
            for _ in 0..<Self.maxConcurrentRequests {
                guard let place = pending.next() else { break }
                group.addTask { (place.id, await Self.fetchMarker(for: place)) }
            }
            for await (id, marker) in group {
                inFlight.remove(id)
                if let marker {
                    cache[id] = CachedMarker(marker: marker, fetchedAt: .now)
                    show(ids)
                }
                if let next = pending.next() {
                    group.addTask { (next.id, await Self.fetchMarker(for: next)) }
                }
            }
        }
        isLoading = !inFlight.isEmpty
    }

    private func show(_ ids: [Int]) {
        let visible = ids.compactMap { cache[$0]?.marker }
        if visible != markers { markers = visible }
    }

    nonisolated private static func fetchMarker(for place: CityIndex.Place) async -> Marker? {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        #if DEBUG
        // Screenshot mode shows a sunny-afternoon map whatever the real time or weather.
        if ScreenshotMode.isActive { return sampleMarker(for: place, at: location) }
        #endif
        guard let current = try? await WeatherService.shared.weather(for: location, including: .current) else {
            return nil
        }
        return Marker(
            id: place.id,
            name: place.name,
            coordinate: location.coordinate,
            emoji: WeatherScene.emoji(for: current.condition, isDaylight: current.isDaylight),
            condition: current.condition.description,
            temperature: current.temperature
        )
    }

    #if DEBUG
    /// Daytime sample weather for screenshots: mostly sun, some clouds and a storm or two,
    /// warmer toward the equator. Stable per place so every capture matches.
    nonisolated private static func sampleMarker(for place: CityIndex.Place, at location: CLLocation) -> Marker {
        let looks: [(String, String)] = [
            ("☀️", "Sunny"), ("⛅️", "Partly Cloudy"), ("☀️", "Sunny"), ("🌤️", "Mostly Sunny"),
            ("🌧️", "Rain"), ("☀️", "Sunny"), ("⛈️", "Thunderstorms"), ("☁️", "Cloudy")
        ]
        let look = looks[abs(place.id) % looks.count]
        let celsius = (31 - abs(place.latitude) * 0.45 + Double(abs(place.id) % 5) - 2).rounded()
        return Marker(
            id: place.id,
            name: place.name,
            coordinate: location.coordinate,
            emoji: look.0,
            condition: look.1,
            temperature: Measurement(value: celsius, unit: .celsius)
        )
    }
    #endif
}

/// About 60,000 towns and cities with 5,000+ people, biggest first, from GeoNames
/// (CC BY 4.0, credited on the map). Bundled as cities.tsv: name, latitude, longitude, population, country code.
struct CityIndex: Sendable {
    struct Place: Sendable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private let names: [String]
    private let latitudes: [Double]
    private let longitudes: [Double]

    static func load() async -> CityIndex? {
        await Task.detached(priority: .userInitiated) { () -> CityIndex? in
            guard let url = Bundle.main.url(forResource: "cities", withExtension: "tsv"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                Logger(subsystem: "EmojiWeather", category: "Map").error("cities.tsv missing from the bundle")
                return nil
            }
            var names: [String] = []
            var latitudes: [Double] = []
            var longitudes: [Double] = []
            names.reserveCapacity(62_000)
            latitudes.reserveCapacity(62_000)
            longitudes.reserveCapacity(62_000)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 3, let lat = Double(fields[1]), let lon = Double(fields[2]) else { continue }
                names.append(String(fields[0]))
                latitudes.append(lat)
                longitudes.append(lon)
            }
            return CityIndex(names: names, latitudes: latitudes, longitudes: longitudes)
        }.value
    }

    /// The biggest places in the clear part of the screen (below the header, above the tab bar,
    /// not cut off at the sides), skipping any too close to a bigger one already picked.
    func places(in region: MKCoordinateRegion, max: Int, spacing: Double) -> [Place] {
        let latSpan = region.span.latitudeDelta
        let lonSpan = region.span.longitudeDelta
        let south = region.center.latitude - latSpan / 2 + latSpan * 0.12
        let north = region.center.latitude + latSpan / 2 - latSpan * 0.16
        let west = region.center.longitude - lonSpan / 2 + lonSpan * 0.08
        let east = region.center.longitude + lonSpan / 2 - lonSpan * 0.08

        // Compare distances in screen-like units: longitude degrees shrink toward the poles.
        let lonScale = cos(region.center.latitude * .pi / 180)
        let shortSide = min(latSpan, lonSpan * lonScale)
        let minDistance = shortSide * spacing

        var picked: [Place] = []
        for index in names.indices {
            let lat = latitudes[index]
            guard lat >= south, lat <= north else { continue }
            var lon = longitudes[index]
            // Bring the longitude into the region's range when the view crosses the date line.
            if lon < west { lon += 360 } else if lon > east + 360 { lon -= 360 }
            guard lon >= west, lon <= east else { continue }

            let crowded = picked.contains { other in
                var otherLon = other.longitude
                if otherLon < west { otherLon += 360 }
                return hypot(other.latitude - lat, (otherLon - lon) * lonScale) < minDistance
            }
            guard !crowded else { continue }
            picked.append(Place(id: index, name: names[index], latitude: lat, longitude: longitudes[index]))
            if picked.count >= max { break }
        }
        return picked
    }
}
