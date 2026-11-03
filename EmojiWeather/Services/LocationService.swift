import CoreLocation
import Foundation
import Observation
import os

/// Asks for "When In Use" location permission and provides the user's current location.
/// City-level accuracy is plenty for weather and is easier on the battery.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    /// A short name for the current location, such as "Cupertino".
    private(set) var placeName: String?
    /// True while waiting for the first location fix.
    private(set) var isLocating = false
    /// Set when Core Location couldn't get a fix, so the UI can say so instead of showing nothing.
    private(set) var failureMessage: String?

    @ObservationIgnored private let logger = Logger(subsystem: "EmojiWeather", category: "Location")

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let geocoder = CLGeocoder()

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // Only report moves of about a kilometer or more: enough to notice a new town or a
        // trip, cheap on the battery.
        manager.distanceFilter = 1_000
    }

    /// Call when the app comes to the foreground: gets a fresh fix right away (in case the
    /// user traveled while the app was closed) and keeps watching for big moves while open.
    func startUpdating() {
        guard isAuthorized else { return }
        refresh()
        manager.startUpdatingLocation()
    }

    /// Call when the app leaves the foreground.
    func stopUpdating() {
        manager.stopUpdatingLocation()
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
        isLocating = location == nil
        failureMessage = nil
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.startUpdating()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            await self.update(to: latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        let description = error.localizedDescription
        Task { @MainActor in
            self.logger.error("Location failed: \(description, privacy: .public)")
            self.isLocating = false
            guard self.location == nil else { return }
            #if targetEnvironment(simulator)
            self.failureMessage = String(localized: "The simulator has no location set. In the Simulator menu, choose Features > Location > Apple, then pull down to refresh.")
            #else
            self.failureMessage = code == .denied
                ? String(localized: "Location access is off.")
                : String(localized: "Couldn't find your location. Pull down to try again.")
            #endif
        }
    }

    private func update(to newLocation: CLLocation) async {
        // Ignore small moves so the weather isn't refetched for every few meters.
        if let location, location.distance(from: newLocation) < 1_000, placeName != nil { return }
        location = newLocation
        isLocating = false
        failureMessage = nil
        let placemark = try? await geocoder.reverseGeocodeLocation(newLocation).first
        placeName = placemark?.locality ?? placemark?.name
    }
}
