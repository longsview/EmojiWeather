import CoreLocation
import Foundation
import Observation
import WeatherKit
#if canImport(FoundationModels) && os(iOS)
import FoundationModels
#endif

/// Everything one screen needs, fetched in a single WeatherKit request.
struct WeatherSnapshot {
    let current: CurrentWeather
    let hourly: [HourWeather]
    /// Hours 24 to 119, added 24 at a time by the hourly strip's arrow. Widgets and the watch only use `hourly`.
    var laterHourly: [HourWeather] = []
    let daily: [DayWeather]
    let fetchedAt: Date
    /// Where the forecast is for, so the forecast sheet can fetch local forecast text.
    var location: CLLocation?
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
        let upcoming = hourly.forecast.filter { $0.date >= startOfHour }
        let snapshot = WeatherSnapshot(
            current: current,
            hourly: Array(upcoming.prefix(24)),
            laterHourly: Array(upcoming.dropFirst(24).prefix(96)),
            daily: Array(daily.forecast.prefix(10)),
            fetchedAt: .now,
            location: location
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

#if os(iOS)
/// Written forecasts from the local National Weather Service office (US only, public domain).
/// api.weather.gov needs no key; it asks apps to send a User-Agent with a contact address.
struct LocalForecast: Equatable {
    struct Period: Equatable, Identifiable {
        let name: String
        let text: String
        var id: String { name }
    }

    /// "Today", "Tonight", "Friday": the office's own plain-English forecast.
    let periods: [Period]
    /// A short summary of the forecasters' Area Forecast Discussion, when there is one.
    let discussion: String?
    /// The issuing office's city, like "Los Angeles/Oxnard".
    let office: String
}

@MainActor
final class LocalForecastService {
    static let shared = LocalForecastService()

    private var cache: [String: (forecast: LocalForecast?, fetchedAt: Date)] = [:]
    private var inFlight: [String: Task<FetchResult, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Skymoji/1.0 (getskymoji@gmail.com)",
            "Accept": "application/geo+json",
        ]
        return URLSession(configuration: config)
    }()

    /// Returns nil outside the US, or when the Weather Service can't be reached.
    func forecast(for location: CLLocation) async -> LocalForecast? {
        let key = Self.key(for: location)
        if let cached = cache[key], Date.now.timeIntervalSince(cached.fetchedAt) < 60 * 60 {
            return cached.forecast
        }
        // The city page prefetches, so the sheet may ask while that fetch is still running.
        if let running = inFlight[key] {
            if case .found(let forecast) = await running.value { return forecast }
            return nil
        }
        let coordinate = location.coordinate
        let task = Task { await fetch(latitude: coordinate.latitude, longitude: coordinate.longitude) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        switch result {
        case .found(let forecast):
            cache[key] = (forecast, .now)
            return forecast
        case .notCovered:
            // Outside the US: remember that, so the sheet doesn't keep asking.
            cache[key] = (nil, .now)
            return nil
        case .failed:
            // The Weather Service often has brief outages; try again next time.
            return nil
        }
    }

    private enum FetchResult { case found(LocalForecast), notCovered, failed }

    /// What's already been fetched, so the forecast sheet can show the card without waiting.
    func cachedForecast(for location: CLLocation) -> LocalForecast? {
        cache[Self.key(for: location)]?.forecast
    }

    /// Starts fetching in the background (the city page calls this once weather is on screen).
    func prefetch(for location: CLLocation) {
        Task { _ = await forecast(for: location) }
    }

    private static func key(for location: CLLocation) -> String {
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }

    private func fetch(latitude: Double, longitude: Double) async -> FetchResult {
        let point = String(format: "%.4f,%.4f", latitude, longitude)
        guard let pointURL = URL(string: "https://api.weather.gov/points/\(point)") else { return .failed }
        let pointsResult: Response<PointsResponse> = await get(pointURL)
        let points: PointsResponse
        switch pointsResult {
        case .ok(let value): points = value
        case .notFound: return .notCovered
        case .failed: return .failed
        }
        guard let forecastURL = points.properties.forecast,
              var components = URLComponents(url: forecastURL, resolvingAgainstBaseURL: false)
        else { return .notCovered }

        if DisplaySettings.temperatureUnit == .celsius {
            components.queryItems = [URLQueryItem(name: "units", value: "si")]
        }
        guard let url = components.url, case .ok(let forecast) = await get(url) as Response<ForecastResponse>
        else { return .failed }
        let periods = forecast.properties.periods.prefix(3).compactMap { period -> LocalForecast.Period? in
            let text = period.detailedForecast.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : LocalForecast.Period(name: period.name, text: text)
        }
        guard !periods.isEmpty else { return .failed }

        var discussion: String?
        if let office = points.properties.cwa, let text = await discussionText(office: office) {
            discussion = await DiscussionSummarizer.summary(of: text)
        }
        let officeName = points.properties.relativeLocation?.properties.city ?? points.properties.cwa ?? ""
        return .found(LocalForecast(periods: Array(periods), discussion: discussion, office: officeName))
    }

    /// The latest Area Forecast Discussion's text for an office, like "LOX".
    private func discussionText(office: String) async -> String? {
        guard let listURL = URL(string: "https://api.weather.gov/products/types/AFD/locations/\(office)"),
              case .ok(let list) = await get(listURL) as Response<ProductList>,
              let latest = list.graph.first?.id,
              case .ok(let product) = await get(latest) as Response<Product> else { return nil }
        return product.productText
    }

    private enum Response<T> { case ok(T), notFound, failed }

    /// GETs and decodes JSON. The Weather Service's gridpoint forecasts often fail for a moment
    /// (500 or 503), so server errors are retried twice before giving up.
    private func get<T: Decodable>(_ url: URL) async -> Response<T> {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 1.5)) }
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 { return .notFound }
                if status >= 500 { continue }
                guard status == 200 else { return .failed }
                return .ok(try JSONDecoder().decode(T.self, from: data))
            } catch is DecodingError {
                return .failed
            } catch {
                continue
            }
        }
        return .failed
    }

    // MARK: - api.weather.gov responses (only the fields Skymoji reads)

    private struct PointsResponse: Decodable {
        struct Properties: Decodable {
            struct RelativeLocation: Decodable {
                struct Place: Decodable { let city: String? }
                let properties: Place
            }
            let forecast: URL?
            let cwa: String?
            let relativeLocation: RelativeLocation?
        }
        let properties: Properties
    }

    private struct ForecastResponse: Decodable {
        struct Properties: Decodable {
            struct Period: Decodable {
                let name: String
                let detailedForecast: String
            }
            let periods: [Period]
        }
        let properties: Properties
    }

    private struct ProductList: Decodable {
        struct Item: Decodable {
            let id: URL
            enum CodingKeys: String, CodingKey { case id = "@id" }
        }
        let graph: [Item]
        enum CodingKeys: String, CodingKey { case graph = "@graph" }
    }

    private struct Product: Decodable {
        let productText: String
    }
}

/// Turns a forecast discussion (written in forecaster shorthand) into two or three plain sentences.
/// Uses Apple's on-device model when it's available, otherwise the discussion's own key messages.
enum DiscussionSummarizer {
    static func summary(of discussion: String) async -> String? {
        let excerpt = keySection(of: discussion)
        guard !excerpt.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let summary = await modelSummary(of: excerpt) {
            return summary
        }
        #endif
        return shortened(excerpt)
    }

    /// The part worth reading: key messages if the office wrote them, else the synopsis,
    /// else the short-term discussion.
    static func keySection(of text: String) -> String {
        let sections = text.components(separatedBy: "\n.")
        let wanted = ["KEY MESSAGES", "SYNOPSIS", "SHORT TERM", "DISCUSSION"]
        for name in wanted {
            if let section = sections.first(where: { $0.uppercased().hasPrefix(name) }) {
                // Drop the header ("SYNOPSIS...") and the closing "&&".
                var body = section
                if let range = body.range(of: "...") { body = String(body[range.upperBound...]) }
                body = body.components(separatedBy: "&&").first ?? body
                var cleaned = body
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Sections often open with an issue time, like "12/1253 PM." or
                // "Issued at 1253 PM PST Thu Nov 12 2026...".
                cleaned = cleaned
                    .replacingOccurrences(of: #"^(Issued at )?\d{1,2}/\d{3,4} ?[AP]M( [A-Z]{3})?\.*\s*"#,
                                          with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"^(Issued at )?\d{3,4} [AP]M [A-Z]{3}( \w{3}){2} \d{1,2} \d{4}\.*\s*"#,
                                          with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count > 40 { return String(cleaned.prefix(2_500)) }
            }
        }
        return ""
    }

    /// The first couple of sentences, in sentence case (discussions are often all capitals).
    static func shortened(_ text: String) -> String {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespaces)) }
            if sentences.count == 2 { stop = true }
        }
        var result = sentences.joined(separator: " ")
        if result.count > 360 { result = String(result.prefix(357)) + "…" }
        if result == result.uppercased() { result = result.lowercased().capitalizedSentences }
        return result
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func modelSummary(of excerpt: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You rewrite National Weather Service forecast discussions for the public. \
            Write two or three short, plain sentences about what the local forecasters expect \
            over the next few days. No jargon, no abbreviations, no greetings, no advice.
            """)
        do {
            let response = try await session.respond(to: "Forecast discussion:\n\(excerpt)")
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
    #endif
}

private extension String {
    /// "THE STORM ARRIVES. RAIN." becomes "The storm arrives. Rain."
    var capitalizedSentences: String {
        var result = ""
        var capitalizeNext = true
        for character in self {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: character.uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
            }
            if ".!?".contains(character) { capitalizeNext = true }
        }
        return result
    }
}
#endif
