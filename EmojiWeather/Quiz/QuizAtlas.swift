import CoreLocation
import Foundation
import os

/// The places the daily quiz asks about, loaded from the bundled lists:
/// - cities.tsv: GeoNames towns and cities with 5,000+ people (CC BY 4.0).
/// - countries.tsv: UN member countries with their capital, flag and region, from
///   mledoze/countries (ODbL 1.0). Country names are shown in the user's language by iOS.
struct QuizAtlas: Sendable {
    struct City: Sendable, Hashable {
        let name: String
        let latitude: Double
        let longitude: Double
        let population: Int
        let countryCode: String

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    struct Country: Sendable, Hashable {
        let code: String
        let flag: String
        let capital: String
        let region: String
        let subregion: String
        let englishName: String

        /// The country's name in the user's language, e.g. "Allemagne" in French.
        var name: String {
            Locale.current.localizedString(forRegionCode: code) ?? englishName
        }
    }

    let cities: [City]
    let countries: [Country]
    private let countriesByCode: [String: Country]

    init(cities: [City], countries: [Country]) {
        self.cities = cities
        self.countries = countries
        countriesByCode = Dictionary(countries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func country(_ code: String) -> Country? { countriesByCode[code] }

    /// The flag emoji for a country code, or an empty string.
    func flag(_ code: String) -> String { countriesByCode[code]?.flag ?? "" }

    static func load() async -> QuizAtlas? {
        await Task.detached(priority: .userInitiated) { () -> QuizAtlas? in
            guard let citiesURL = Bundle.main.url(forResource: "cities", withExtension: "tsv"),
                  let countriesURL = Bundle.main.url(forResource: "countries", withExtension: "tsv"),
                  let citiesText = try? String(contentsOf: citiesURL, encoding: .utf8),
                  let countriesText = try? String(contentsOf: countriesURL, encoding: .utf8) else {
                Logger(subsystem: "EmojiWeather", category: "Quiz").error("Quiz data missing from the bundle")
                return nil
            }
            var cities: [City] = []
            cities.reserveCapacity(62_000)
            for line in citiesText.split(separator: "\n", omittingEmptySubsequences: true) {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 5,
                      let lat = Double(fields[1]), let lon = Double(fields[2]),
                      let population = Int(fields[3]) else { continue }
                cities.append(City(
                    name: String(fields[0]), latitude: lat, longitude: lon,
                    population: population, countryCode: String(fields[4])
                ))
            }
            var countries: [Country] = []
            for line in countriesText.split(separator: "\n", omittingEmptySubsequences: true) {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 6 else { continue }
                countries.append(Country(
                    code: String(fields[0]), flag: String(fields[1]), capital: String(fields[2]),
                    region: String(fields[3]), subregion: String(fields[4]), englishName: String(fields[5])
                ))
            }
            return QuizAtlas(cities: cities, countries: countries)
        }.value
    }
}

/// A small, fast random generator that gives the same numbers for the same seed, so a day's
/// quiz is the same every time it's built that day.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// Seeds from text, e.g. "2026-11-03|37.3,-122.0".
    init(text: String) {
        // FNV-1a: stable across launches, unlike Swift's Hasher.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
