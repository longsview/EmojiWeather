import CoreLocation
import MapKit
import Observation
import os
import WeatherKit

/// Weather for the emoji map. The visible area is split into a grid of squares and each square
/// gets one WeatherKit call for its center, cached for 30 minutes. Zooming out uses bigger
/// squares, so a screen always holds a couple of dozen markers at most.
@MainActor
@Observable
final class MapWeatherModel {
    struct Marker: Identifiable, Equatable {
        let id: CellKey
        let coordinate: CLLocationCoordinate2D
        let emoji: String
        let temperature: Measurement<UnitTemperature>

        static func == (lhs: Marker, rhs: Marker) -> Bool {
            lhs.id == rhs.id && lhs.emoji == rhs.emoji && lhs.temperature == rhs.temperature
        }
    }

    struct CellKey: Hashable {
        /// Index into `cellSizes`.
        let level: Int
        let row: Int
        let column: Int
    }

    private struct CachedCell {
        let marker: Marker
        let fetchedAt: Date
    }

    /// Square sizes in degrees, smallest first.
    private static let cellSizes: [Double] = [0.1, 0.15, 0.25, 0.4, 0.6, 1, 1.5, 2.5, 4, 6, 10, 16]
    /// Aim for about this many squares across the shorter side of the screen.
    private static let cellsAcross = 3.5
    private static let maxCellsPerUpdate = 30
    private static let maxAge: TimeInterval = 30 * 60
    private static let maxConcurrentRequests = 6

    private(set) var markers: [Marker] = []
    private(set) var isLoading = false

    @ObservationIgnored private var cache: [CellKey: CachedCell] = [:]
    @ObservationIgnored private var inFlight: Set<CellKey> = []
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "EmojiWeather", category: "Map")

    /// Call when the map stops moving.
    func update(region: MKCoordinateRegion) {
        updateTask?.cancel()
        updateTask = Task {
            // Wait for the map to settle so a long pan is one batch of calls, not many.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load(region: region)
        }
    }

    private func load(region: MKCoordinateRegion) async {
        let (level, cells) = Self.cells(in: region)
        showMarkers(level: level, cells: cells)

        let now = Date.now
        let missing = cells.filter { key in
            guard !inFlight.contains(key) else { return false }
            guard let cached = cache[key] else { return true }
            return now.timeIntervalSince(cached.fetchedAt) > Self.maxAge
        }
        guard !missing.isEmpty else { return }

        isLoading = true
        defer { isLoading = inFlight.isEmpty == false }
        inFlight.formUnion(missing)

        await withTaskGroup(of: (CellKey, Marker?).self) { group in
            var pending = missing.makeIterator()
            // At most a few requests at a time; each finished one starts the next.
            for _ in 0..<Self.maxConcurrentRequests {
                guard let key = pending.next() else { break }
                let center = Self.center(of: key)
                group.addTask { (key, await Self.fetchMarker(key: key, center: center)) }
            }
            for await (key, marker) in group {
                inFlight.remove(key)
                if let marker {
                    cache[key] = CachedCell(marker: marker, fetchedAt: .now)
                    showMarkers(level: level, cells: cells)
                }
                if let next = pending.next() {
                    let center = Self.center(of: next)
                    group.addTask { (next, await Self.fetchMarker(key: next, center: center)) }
                }
            }
        }
    }

    private func showMarkers(level: Int, cells: [CellKey]) {
        let visible = cells.compactMap { cache[$0]?.marker }
        if visible != markers { markers = visible }
    }

    nonisolated private static func fetchMarker(key: CellKey, center: CLLocationCoordinate2D) async -> Marker? {
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        do {
            let current = try await WeatherService.shared.weather(for: location, including: .current)
            return Marker(
                id: key,
                coordinate: center,
                emoji: WeatherScene.emoji(for: current.condition, isDaylight: current.isDaylight),
                temperature: current.temperature
            )
        } catch {
            return nil
        }
    }

    // MARK: - Grid

    nonisolated private static func cells(in region: MKCoordinateRegion) -> (level: Int, cells: [CellKey]) {
        let shortSide = min(region.span.latitudeDelta, region.span.longitudeDelta)
        let target = shortSide / cellsAcross
        let level = cellSizes.firstIndex { $0 >= target } ?? cellSizes.count - 1
        let size = cellSizes[level]

        let minLat = max(region.center.latitude - region.span.latitudeDelta / 2, -85)
        let maxLat = min(region.center.latitude + region.span.latitudeDelta / 2, 85)
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        let rows = Int((minLat / size).rounded(.down))...Int((maxLat / size).rounded(.down))
        let columns = Int((minLon / size).rounded(.down))...Int((maxLon / size).rounded(.down))

        // Only squares whose marker lands in the clear part of the screen: below the header,
        // above the tab bar, and not cut off at the sides.
        let visibleLat = (minLat + region.span.latitudeDelta * 0.12)...(maxLat - region.span.latitudeDelta * 0.16)
        let visibleLon = (minLon + region.span.longitudeDelta * 0.08)...(maxLon - region.span.longitudeDelta * 0.08)

        var keys: [CellKey] = []
        for row in rows {
            for column in columns {
                let lat = (Double(row) + 0.5) * size
                let lon = (Double(column) + 0.5) * size
                guard visibleLat.contains(lat), visibleLon.contains(lon) else { continue }
                keys.append(CellKey(level: level, row: row, column: column))
            }
        }
        // Nearest the middle first, so a capped batch still fills the center of the screen.
        let centerRow = region.center.latitude / size
        let centerColumn = region.center.longitude / size
        keys.sort {
            hypot(Double($0.row) + 0.5 - centerRow, Double($0.column) + 0.5 - centerColumn)
                < hypot(Double($1.row) + 0.5 - centerRow, Double($1.column) + 0.5 - centerColumn)
        }
        return (level, Array(keys.prefix(maxCellsPerUpdate)))
    }

    nonisolated private static func center(of key: CellKey) -> CLLocationCoordinate2D {
        let size = cellSizes[key.level]
        var longitude = (Double(key.column) + 0.5) * size
        // Wrap around the date line.
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: (Double(key.row) + 0.5) * size, longitude: longitude)
    }
}
