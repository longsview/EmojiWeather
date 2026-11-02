import CoreLocation
import Foundation

/// A saved city. Saved cities are synced to every device through iCloud (see `CityStore`).
struct City: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// Extra context shown under the name, e.g. "California, United States".
    var region: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String?

    init(
        id: UUID = UUID(),
        name: String,
        region: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// Two entries closer than about 1 km count as the same place, so a city can't be added twice.
    func isSamePlace(as other: City) -> Bool {
        abs(latitude - other.latitude) < 0.01 && abs(longitude - other.longitude) < 0.01
    }
}

/// What the home screen is showing: the user's current location or one of their saved cities.
enum Place: Hashable {
    case currentLocation
    case city(City)

    static let currentLocationID = "current"

    var id: String {
        switch self {
        case .currentLocation: Self.currentLocationID
        case .city(let city): city.id.uuidString
        }
    }

    /// Falls back to the current location when the saved selection no longer exists
    /// (for example, the city was deleted on another device).
    static func resolve(id: String, cities: [City]) -> Place {
        if let uuid = UUID(uuidString: id), let city = cities.first(where: { $0.id == uuid }) {
            return .city(city)
        }
        return .currentLocation
    }
}
