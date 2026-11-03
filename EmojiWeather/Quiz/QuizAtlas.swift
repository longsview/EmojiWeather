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
    /// Cities of a million or more, for the world questions. Small enough to scan anywhere.
    let bigCities: [City]
    let countries: [Country]
    private let countriesByCode: [String: Country]

    init(cities: [City], countries: [Country]) {
        self.cities = cities
        bigCities = cities.filter { $0.population >= 1_000_000 }
        self.countries = countries
        countriesByCode = Dictionary(countries.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The places near a point that the local questions need. Scanning 60,000 cities takes a
    /// noticeable moment (much longer in Debug builds), so it runs off the main thread.
    struct Nearby: Sendable {
        /// Towns of 10,000+ between 12 and 250 km away, with their distance in meters.
        let towns: [(city: City, distance: Double)]
        /// Cities of 200,000+ between 150 and 3,000 km away, with their distance in meters.
        let regional: [(city: City, distance: Double)]
    }

    func nearby(latitude: Double, longitude: Double) async -> Nearby {
        let cities = cities
        return await Task.detached(priority: .userInitiated) {
            var towns: [(city: City, distance: Double)] = []
            var regional: [(city: City, distance: Double)] = []
            for city in cities where city.population >= 10_000 {
                let distance = Self.distance(latitude, longitude, city.latitude, city.longitude)
                if distance > 12_000, distance < 250_000 { towns.append((city, distance)) }
                if city.population >= 200_000, distance > 150_000, distance < 3_000_000 {
                    regional.append((city, distance))
                }
            }
            return Nearby(towns: towns, regional: regional)
        }.value
    }

    /// Great-circle distance in meters.
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
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
