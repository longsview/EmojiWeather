import CoreLocation
import Foundation
import WidgetKit

/// Copies what the widgets need into the App Group and asks WidgetKit to redraw.
/// The widgets reuse the app's weather, so they rarely need their own WeatherKit calls.
@MainActor
enum WidgetSync {
    static func updatePlaces(cities: [City], currentLocation: CLLocation?, currentName: String?, hasPlus: Bool) {
        #if DEBUG && os(watchOS)
        // The watch app seeds sample places for screenshot complications; keep them.
        if ScreenshotMode.scene != nil { return }
        #endif
        var places: [WidgetPlace] = []
        if let currentLocation {
            places.append(WidgetPlace(
                id: WidgetPlace.currentLocationID,
                name: currentName ?? String(localized: "My Location"),
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                timeZoneIdentifier: TimeZone.current.identifier
            ))
        }
        places += cities.map {
            WidgetPlace(
                id: $0.id.uuidString,
                name: $0.name,
                latitude: $0.latitude,
                longitude: $0.longitude,
                timeZoneIdentifier: $0.timeZoneIdentifier
            )
        }

        guard places != SharedStore.places || hasPlus != SharedStore.hasPlus else { return }
        SharedStore.places = places
        SharedStore.hasPlus = hasPlus
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func save(_ snapshot: WeatherSnapshot, for place: Place) {
        let weather = WidgetWeather(
            current: snapshot.current,
            hourly: snapshot.hourly,
            daily: snapshot.daily,
            fetchedAt: snapshot.fetchedAt
        )
        guard SharedStore.weather(for: place.id) != weather else { return }
        SharedStore.setWeather(weather, for: place.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
