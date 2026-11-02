import CoreLocation
import Foundation
import Observation

/// Asks for "When In Use" location permission and provides the user's current location.
/// City-level accuracy is plenty for weather and is easier on the battery.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    /// A short name for the current location, such as "Cupertino".
    private(set) var placeName: String?

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let geocoder = CLGeocoder()

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// True when the user turned location off, so the app can point them to Settings.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Shows the system permission prompt. Only call this after the user taps a button that
    /// explains why the app wants their location.
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            await self.update(to: latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Usually a temporary failure (no GPS fix yet). The next refresh will try again.
    }

    private func update(to newLocation: CLLocation) async {
        // Ignore small moves so the weather isn't refetched for every few meters.
        if let location, location.distance(from: newLocation) < 1_000, placeName != nil { return }
        location = newLocation
        let placemark = try? await geocoder.reverseGeocodeLocation(newLocation).first
        placeName = placemark?.locality ?? placemark?.name
    }
}
