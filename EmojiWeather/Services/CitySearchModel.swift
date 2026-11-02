import Foundation
import MapKit
import Observation

/// Type-ahead city search for the Add City screen, backed by MapKit (no API key or backend needed).
@MainActor
@Observable
final class CitySearchModel: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var pendingQuery: Task<Void, Never>?

    enum SearchError: LocalizedError {
        case notFound
        var errorDescription: String? { "We couldn't find that place. Try another search." }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    /// Debounced: MapKit is only asked after the user pauses typing for a moment, so fast typing
    /// doesn't queue up a search per keystroke.
    func update(query: String) {
        pendingQuery?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if completer.isSearching { completer.cancel() }
            if !results.isEmpty { results = [] }
            return
        }
        pendingQuery = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            if self.completer.queryFragment != trimmed {
                self.completer.queryFragment = trimmed
            }
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
