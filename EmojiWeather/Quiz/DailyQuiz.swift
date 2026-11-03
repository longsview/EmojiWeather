import CoreLocation
import Foundation
import WeatherKit

/// One multiple-choice question.
struct QuizQuestion: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case closestTown, direction, hotterColder, whereWeather, capital, flag
    }

    struct Option: Codable, Hashable {
        var emoji: String = ""
        var text: String
    }

    var id: Int
    var kind: Kind
    /// Big emoji at the top of the card.
    var emoji: String
    var prompt: String
    var options: [Option]
    var correctIndex: Int
    /// Shown after answering, e.g. "Denver is 1,240 km to the northeast."
    var explanation: String
    var chosenIndex: Int?

    var isAnswered: Bool { chosenIndex != nil }
    var isCorrect: Bool { chosenIndex == correctIndex }
}

/// Today's quiz: five questions, the same all day.
struct DailyQuiz: Codable, Hashable {
    /// "2026-11-03" in the user's calendar.
    var day: String
    /// "Skymoji Daily #12".
    var number: Int
    var questions: [QuizQuestion]

    var isFinished: Bool { questions.allSatisfy(\.isAnswered) }
    var score: Int { questions.filter(\.isCorrect).count }

    /// ☀️ for right, 🌧️ for wrong, ⬜️ for not answered yet.
    var grid: String {
        questions.map { question in
            guard question.isAnswered else { return "⬜️" }
            return question.isCorrect ? "☀️" : "🌧️"
        }.joined()
    }
}

/// Builds the day's questions from the bundled places, the user's location and live weather.
/// Every question has a fallback (capitals and flags), so a quiz always has five questions
/// even with no location or no network.
@MainActor
struct QuizBuilder {
    let atlas: QuizAtlas
    let weather: WeatherProvider
    /// Where the user is, or nil (no location permission and no saved city).
    let origin: CLLocation?
    let day: String
    let number: Int

    private static let compass: [(emoji: String, name: () -> String)] = [
        ("⬆️", { String(localized: "North") }),
        ("↗️", { String(localized: "Northeast") }),
        ("➡️", { String(localized: "East") }),
        ("↘️", { String(localized: "Southeast") }),
        ("⬇️", { String(localized: "South") }),
        ("↙️", { String(localized: "Southwest") }),
        ("⬅️", { String(localized: "West") }),
        ("↖️", { String(localized: "Northwest") }),
    ]

    func build() async -> DailyQuiz {
        // Same seed all day in the same area, so rebuilding gives the same quiz.
        let area = origin.map { String(format: "%.0f,%.0f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "none"
        var rng = SeededGenerator(text: "\(day)|\(area)")

        var questions: [QuizQuestion] = []
        func add(_ question: QuizQuestion?) {
            guard var question else { return }
            question.id = questions.count
            questions.append(question)
        }

        if let origin {
            add(closestTown(from: origin, rng: &rng) ?? capital(rng: &rng))
            add(direction(from: origin, rng: &rng) ?? flag(rng: &rng))
            add(await hotterColder(from: origin, rng: &rng) ?? capital(rng: &rng))
        } else {
            add(capital(rng: &rng))
            add(flag(rng: &rng))
            add(capital(rng: &rng))
        }
        add(await whereWeather(rng: &rng) ?? flag(rng: &rng))
        add(Bool.random(using: &rng) ? capital(rng: &rng) : flag(rng: &rng))

        return DailyQuiz(day: day, number: number, questions: questions)
    }

    // MARK: - Near you

    /// "Which of these is closest to you?"
    private func closestTown(from origin: CLLocation, rng: inout SeededGenerator) -> QuizQuestion? {
        let nearby = atlas.cities
            .filter { $0.population >= 10_000 }
            .map { ($0, $0.location.distance(from: origin)) }
            .filter { $0.1 > 12_000 && $0.1 < 250_000 }
        var seen = Set<String>()
        let unique = nearby.filter { seen.insert($0.0.name).inserted }
        guard unique.count >= 4 else { return nil }
        // Four towns whose distances differ by at least 15%, so the answer is clear.
        var picks: [(QuizAtlas.City, Double)] = []
        for candidate in unique.shuffled(using: &rng) {
            if picks.allSatisfy({ abs($0.1 - candidate.1) / max($0.1, candidate.1) > 0.15 }) {
                picks.append(candidate)
            }
            if picks.count == 4 { break }
        }
        guard picks.count == 4 else { return nil }
        let answer = picks.min { $0.1 < $1.1 }!
        let answerName = answer.0.name
        let answerDistance = Self.distance(answer.1)
        return QuizQuestion(
            id: 0, kind: .closestTown, emoji: "📍",
            prompt: String(localized: "Which of these is closest to you?"),
            options: picks.map { .init(emoji: atlas.flag($0.0.countryCode), text: $0.0.name) },
            correctIndex: picks.firstIndex { $0.0 == answer.0 }!,
            explanation: String(localized: "\(answerName) is \(answerDistance) away.")
        )
    }

    /// "Which way is Denver from you?"
    private func direction(from origin: CLLocation, rng: inout SeededGenerator) -> QuizQuestion? {
        let candidates = atlas.cities.filter {
            guard $0.population >= 200_000 else { return false }
            let distance = $0.location.distance(from: origin)
            return distance > 150_000 && distance < 3_000_000
        }
        guard let city = candidates.randomElement(using: &rng) else { return nil }
        let bearing = Self.bearing(from: origin.coordinate, to: city.location.coordinate)
        let correct = Int((bearing / 45).rounded()) % 8
        // The right direction plus three others, in compass order.
        var others = Array(0..<8).filter { $0 != correct }.shuffled(using: &rng).prefix(3)
        others.append(correct)
        let indexes = others.sorted()
        let cityName = city.name
        let distanceText = Self.distance(city.location.distance(from: origin))
        let directionName = Self.compass[correct].name().lowercased()
        return QuizQuestion(
            id: 0, kind: .direction, emoji: "🧭",
            prompt: String(localized: "Which way is \(city.name) from you?"),
            options: indexes.map { .init(emoji: Self.compass[$0].emoji, text: Self.compass[$0].name()) },
            correctIndex: indexes.firstIndex(of: correct)!,
            explanation: String(localized: "\(cityName) is \(distanceText) to the \(directionName).")
        )
    }

    /// "Is it warmer in Lisbon or where you are right now?"
    private func hotterColder(from origin: CLLocation, rng: inout SeededGenerator) async -> QuizQuestion? {
        guard let here = try? await weather.weather(for: origin) else { return nil }
        let bigCities = atlas.cities.filter { $0.population >= 1_000_000 && $0.location.distance(from: origin) > 1_000_000 }
        for city in bigCities.shuffled(using: &rng).prefix(3) {
            guard let there = try? await weather.weather(for: city.location) else { continue }
            let hereValue = here.current.temperature.converted(to: .celsius).value
            let thereValue = there.current.temperature.converted(to: .celsius).value
            // Skip near-ties; nobody can call those.
            guard abs(hereValue - thereValue) >= 2 else { continue }
            return QuizQuestion(
                id: 0, kind: .hotterColder, emoji: "🌡️",
                prompt: String(localized: "Right now, is it warmer or colder in \(city.name) than where you are?"),
                options: [
                    .init(emoji: "🥵", text: String(localized: "Warmer there")),
                    .init(emoji: "🥶", text: String(localized: "Colder there")),
                ],
                correctIndex: thereValue > hereValue ? 0 : 1,
                explanation: String(localized: "It's \(there.current.temperature.shortTemperature) in \(city.name) and \(here.current.temperature.shortTemperature) where you are.")
            )
        }
        return nil
    }

    // MARK: - Around the world

    /// "Where is it ⛈️ right now?" when one city's sky stands out, otherwise "Where is it warmest?"
    private func whereWeather(rng: inout SeededGenerator) async -> QuizQuestion? {
        let bigCities = atlas.cities.filter { $0.population >= 1_000_000 }.shuffled(using: &rng)
        var picks: [QuizAtlas.City] = []
        var countries = Set<String>()
        for city in bigCities where countries.insert(city.countryCode).inserted {
            picks.append(city)
            if picks.count == 4 { break }
        }
        var readings: [(city: QuizAtlas.City, emoji: String, temperature: Measurement<UnitTemperature>)] = []
        for city in picks {
            guard let snapshot = try? await weather.weather(for: city.location) else { return nil }
            let conditions = SceneConditions(current: snapshot.current, today: snapshot.daily.first)
            readings.append((city, conditions.scene.emoji(in: conditions.sky), snapshot.current.temperature))
        }
        guard readings.count == 4 else { return nil }

        let summary = readings
            .map { "\($0.city.name) \($0.emoji) \($0.temperature.shortTemperature)" }
            .joined(separator: " · ")
        let options = readings.map { QuizQuestion.Option(emoji: atlas.flag($0.city.countryCode), text: $0.city.name) }

        let emojiCounts = Dictionary(grouping: readings, by: \.emoji)
        if let standout = readings.first(where: { emojiCounts[$0.emoji]?.count == 1 }), emojiCounts.count > 1 {
            return QuizQuestion(
                id: 0, kind: .whereWeather, emoji: standout.emoji,
                prompt: String(localized: "Where is it \(standout.emoji) right now?"),
                options: options,
                correctIndex: readings.firstIndex { $0.city == standout.city }!,
                explanation: summary
            )
        }
        let warmest = readings.max { $0.temperature.converted(to: .celsius).value < $1.temperature.converted(to: .celsius).value }!
        return QuizQuestion(
            id: 0, kind: .whereWeather, emoji: "🔥",
            prompt: String(localized: "Where is it warmest right now?"),
            options: options,
            correctIndex: readings.firstIndex { $0.city == warmest.city }!,
            explanation: summary
        )
    }

    /// "What's the capital of Portugal?" with three capitals from the same part of the world.
    private func capital(rng: inout SeededGenerator) -> QuizQuestion? {
        guard let country = atlas.countries.randomElement(using: &rng) else { return nil }
        let others = sameArea(as: country, rng: &rng)
        let choices = (others + [country]).shuffled(using: &rng)
        return QuizQuestion(
            id: 0, kind: .capital, emoji: country.flag,
            prompt: String(localized: "What's the capital of \(country.name)?"),
            options: choices.map { .init(text: $0.capital) },
            correctIndex: choices.firstIndex(of: country)!,
            explanation: String(localized: "\(country.capital) is the capital of \(country.name).")
        )
    }

    /// "Which country has this flag?"
    private func flag(rng: inout SeededGenerator) -> QuizQuestion? {
        guard let country = atlas.countries.randomElement(using: &rng) else { return nil }
        let others = sameArea(as: country, rng: &rng)
        let choices = (others + [country]).shuffled(using: &rng)
        return QuizQuestion(
            id: 0, kind: .flag, emoji: country.flag,
            prompt: String(localized: "Which country has this flag?"),
            options: choices.map { .init(text: $0.name) },
            correctIndex: choices.firstIndex(of: country)!,
            explanation: String(localized: "That's the flag of \(country.name). Its capital is \(country.capital).")
        )
    }

    /// Three other countries, from the same subregion when there are enough.
    private func sameArea(as country: QuizAtlas.Country, rng: inout SeededGenerator) -> [QuizAtlas.Country] {
        var pool = atlas.countries.filter { $0.subregion == country.subregion && $0 != country }
        if pool.count < 3 { pool = atlas.countries.filter { $0.region == country.region && $0 != country } }
        if pool.count < 3 { pool = atlas.countries.filter { $0 != country } }
        return Array(pool.shuffled(using: &rng).prefix(3))
    }

    // MARK: - Helpers

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Initial compass bearing in degrees, 0 = north, clockwise.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
