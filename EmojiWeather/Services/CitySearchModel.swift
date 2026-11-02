import Foundation
import MapKit
import Observation

/// Type-ahead city search for the Add City screen, backed by MapKit (no API key or backend needed).
@MainActor
@Observable
final class CitySearchModel: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    enum SearchError: LocalizedError {
        case notFound
        var errorDescription: String? { "We couldn't find that place. Try another search." }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            completer.cancel()
        } else {
            completer.queryFragment = trimmed
        }
    }

    /// Turns a search suggestion into a `City` with coordinates and a time zone.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> City {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw SearchError.notFound }

        let coordinate = item.placemark.coordinate
        let name = completion.title.components(separatedBy: ",").first ?? completion.title
        return City(
            name: name.trimmingCharacters(in: .whitespaces),
            region: completion.subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let latest = completer.results
        Task { @MainActor in
            self.results = latest
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}
