import CoreLocation
import Foundation
import WeatherKit

/// One multiple-choice question.
struct QuizQuestion: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case closestTown, direction, hotterColder, whereWeather, capital, flag
        case continent, cityCountry, northernmost, biggestCity, borders, landlocked, largestCountry

        /// Needs to know where the user is.
        var needsLocation: Bool { [.closestTown, .direction, .hotterColder].contains(self) }
        /// Uses live weather.
        var usesWeather: Bool { [.hotterColder, .whereWeather].contains(self) }
    }

    /// The quiz starts easy and gets harder: easy, easy, medium, medium, hard.
    enum Difficulty: String, Codable {
        case easy, medium, hard

        var title: String {
            switch self {
            case .easy: String(localized: "Easy")
            case .medium: String(localized: "Medium")
            case .hard: String(localized: "Hard")
            }
        }

        /// Which kinds of question fit each level.
        var kinds: [Kind] {
            switch self {
            case .easy: [.closestTown, .hotterColder, .flag, .capital, .continent]
            case .medium: [.direction, .cityCountry, .biggestCity, .borders, .landlocked, .largestCountry]
            case .hard: [.whereWeather, .flag, .capital, .borders, .closestTown, .northernmost]
            }
        }
    }

    struct Option: Codable, Hashable {
        var emoji: String = ""
        var text: String
    }

    var id: Int
    var kind: Kind
    /// Missing in quizzes saved before levels existed.
    var difficulty: Difficulty?
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
/// Five questions that get harder (see `plan`), each a different kind. Flags and capitals are
/// the fallback, so a quiz always has five questions even with no location or no network.
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

    static let plan: [QuizQuestion.Difficulty] = [.easy, .easy, .medium, .medium, .hard]

    func build() async -> DailyQuiz {
        // Same seed all day in the same area, so rebuilding gives the same quiz.
        let area = origin.map { String(format: "%.0f,%.0f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "none"
        var rng = SeededGenerator(text: "\(day)|\(area)")

        var nearby: QuizAtlas.Nearby?
        if let origin {
            nearby = await atlas.nearby(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude)
        }

        var questions: [QuizQuestion] = []
        var used = Set<QuizQuestion.Kind>()
        for (slot, level) in Self.plan.enumerated() {
            var kinds = level.kinds.filter { !used.contains($0) && (origin != nil || !$0.needsLocation) }
                .shuffled(using: &rng)
            // Start near you when we know where you are.
            if slot == 0, origin != nil {
                kinds.sort { $0.needsLocation && !$1.needsLocation }
            }
            // Make sure the weather shows up once.
            if slot == Self.plan.count - 1, !used.contains(where: \.usesWeather) {
                kinds.sort { $0.usesWeather && !$1.usesWeather }
            }
            var question: QuizQuestion?
            for kind in kinds {
                question = await make(kind, level: level, nearby: nearby, rng: &rng)
                if question != nil { break }
            }
            // Flags and capitals always work, even offline.
            if question == nil { question = flag(level: level, rng: &rng) ?? capital(level: level, rng: &rng) }
            guard var question else { continue }
            question.id = questions.count
            question.difficulty = level
            used.insert(question.kind)
            questions.append(question)
        }
        return DailyQuiz(day: day, number: number, questions: questions)
    }

    private func make(
        _ kind: QuizQuestion.Kind, level: QuizQuestion.Difficulty, nearby: QuizAtlas.Nearby?,
        rng: inout SeededGenerator
    ) async -> QuizQuestion? {
        switch kind {
        case .closestTown:
            guard let nearby else { return nil }
            return closestTown(nearby, level: level, rng: &rng)
        case .direction:
            guard let origin, let nearby else { return nil }
            return direction(from: origin, nearby: nearby, rng: &rng)
        case .hotterColder:
            guard let origin else { return nil }
            return await hotterColder(from: origin, rng: &rng)
        case .whereWeather: return await whereWeather(rng: &rng)
        case .capital: return capital(level: level, rng: &rng)
        case .flag: return flag(level: level, rng: &rng)
        case .continent: return continent(rng: &rng)
        case .cityCountry: return cityCountry(rng: &rng)
        case .northernmost: return northernmost(level: level, rng: &rng)
        case .biggestCity: return biggestCity(level: level, rng: &rng)
        case .borders: return borders(level: level, rng: &rng)
        case .landlocked: return landlocked(rng: &rng)
        case .largestCountry: return largestCountry(level: level, rng: &rng)
        }
    }

    // MARK: - Near you

    /// "Which of these is closest to you?"
    private func closestTown(_ nearby: QuizAtlas.Nearby, level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        var seen = Set<String>()
        let unique = nearby.towns.map { ($0.city, $0.distance) }.filter { seen.insert($0.0.name).inserted }
        guard unique.count >= 4 else { return nil }
        // Four towns whose distances differ enough that the answer is clear: by half on easy
        // days, by only 15% on hard ones.
        let gap = level == .easy ? 0.5 : 0.15
        var picks: [(QuizAtlas.City, Double)] = []
        for candidate in unique.shuffled(using: &rng) {
            if picks.allSatisfy({ abs($0.1 - candidate.1) / max($0.1, candidate.1) > gap }) {
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
    private func direction(from origin: CLLocation, nearby: QuizAtlas.Nearby, rng: inout SeededGenerator) -> QuizQuestion? {
        guard let city = nearby.regional.randomElement(using: &rng)?.city else { return nil }
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
        let bigCities = atlas.bigCities.filter { $0.location.distance(from: origin) > 1_000_000 }
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
        let bigCities = atlas.bigCities.shuffled(using: &rng)
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

    /// "What's the capital of Portugal?" Easy ones ask about well-known countries; hard ones
    /// about the rest, with three capitals from the same part of the world.
    private func capital(level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        guard let country = pickCountry(level: level, forCapital: true, rng: &rng) else { return nil }
        let others = sameArea(as: country, level: level, rng: &rng)
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
    private func flag(level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        guard let country = pickCountry(level: level, rng: &rng) else { return nil }
        let others = sameArea(as: country, level: level, rng: &rng)
        let choices = (others + [country]).shuffled(using: &rng)
        return QuizQuestion(
            id: 0, kind: .flag, emoji: country.flag,
            prompt: String(localized: "Which country has this flag?"),
            options: choices.map { .init(text: $0.name) },
            correctIndex: choices.firstIndex(of: country)!,
            explanation: String(localized: "That's the flag of \(country.name). Its capital is \(country.capital).")
        )
    }

    /// "Which continent is Kenya in?"
    private func continent(rng: inout SeededGenerator) -> QuizQuestion? {
        let pool = atlas.countries.filter { $0.isWellKnown && !$0.needsArticle && $0.continent != nil }
        guard let country = pool.randomElement(using: &rng), let answer = country.continent else { return nil }
        var choices = Array(QuizAtlas.Continent.allCases.filter { $0 != answer }.shuffled(using: &rng).prefix(3))
        choices.append(answer)
        choices.shuffle(using: &rng)
        let countryName = country.name
        let continentName = answer.name
        return QuizQuestion(
            id: 0, kind: .continent, emoji: country.flag,
            prompt: String(localized: "Which continent is \(countryName) in?"),
            options: choices.map { .init(emoji: $0.emoji, text: $0.name) },
            correctIndex: choices.firstIndex(of: answer)!,
            explanation: String(localized: "\(countryName) is in \(continentName).")
        )
    }

    /// "Which country is Osaka in?"
    private func cityCountry(rng: inout SeededGenerator) -> QuizQuestion? {
        for city in atlas.bigCities.shuffled(using: &rng).prefix(20) {
            // Skip cities that share their country's name, like Mexico City or Singapore.
            guard let country = atlas.country(city.countryCode), !country.needsArticle,
                  !city.name.localizedCaseInsensitiveContains(country.englishName),
                  !country.englishName.localizedCaseInsensitiveContains(city.name) else { continue }
            let others = sameArea(as: country, level: .hard, rng: &rng)
            let choices = (others + [country]).shuffled(using: &rng)
            let cityName = city.name
            let countryName = country.name
            return QuizQuestion(
                id: 0, kind: .cityCountry, emoji: "🏙️",
                prompt: String(localized: "Which country is \(cityName) in?"),
                options: choices.map { .init(emoji: $0.flag, text: $0.name) },
                correctIndex: choices.firstIndex(of: country)!,
                explanation: String(localized: "\(cityName) is in \(countryName).")
            )
        }
        return nil
    }

    /// "Which of these cities is furthest north?" Hard days pick cities only a few degrees apart.
    private func northernmost(level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        let gap: ClosedRange<Double> = level == .hard ? 1.5...6 : 4...15
        guard let picks = pickCities(from: atlas.bigCities, rng: &rng, apart: { abs($0.latitude - $1.latitude) }, in: gap)
        else { return nil }
        let answer = picks.max { $0.latitude < $1.latitude }!
        let summary = picks
            .sorted { $0.latitude > $1.latitude }
            .map { "\($0.name) \(Self.latitude($0.latitude))" }
            .joined(separator: " · ")
        return QuizQuestion(
            id: 0, kind: .northernmost, emoji: "⬆️",
            prompt: String(localized: "Which of these cities is furthest north?"),
            options: picks.map { .init(emoji: atlas.flag($0.countryCode), text: $0.name) },
            correctIndex: picks.firstIndex(of: answer)!,
            explanation: summary
        )
    }

    /// "Which of these cities has the most people?"
    private func biggestCity(level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        // Close calls, but at least 25% apart so the answer is clear.
        let ratio: ClosedRange<Double> = level == .hard ? 1.25...2 : 1.25...4
        guard let picks = pickCities(
            from: atlas.largeCities, rng: &rng,
            apart: { Double(max($0.population, $1.population)) / Double(max(min($0.population, $1.population), 1)) },
            in: ratio
        ) else { return nil }
        let answer = picks.max { $0.population < $1.population }!
        let summary = picks
            .sorted { $0.population > $1.population }
            .map { "\($0.name) \($0.population.formatted(.number.notation(.compactName)))" }
            .joined(separator: " · ")
        return QuizQuestion(
            id: 0, kind: .biggestCity, emoji: "👥",
            prompt: String(localized: "Which of these cities has the most people?"),
            options: picks.map { .init(emoji: atlas.flag($0.countryCode), text: $0.name) },
            correctIndex: picks.firstIndex(of: answer)!,
            explanation: summary
        )
    }

    /// "Which of these countries borders Brazil?" The others are nearby but don't.
    private func borders(level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        let pool = atlas.countries.filter { !$0.borders.isEmpty && !$0.needsArticle && (level == .hard) != $0.isWellKnown }
        for country in pool.shuffled(using: &rng).prefix(10) {
            let neighbors = country.borders.compactMap { atlas.country($0) }.filter { !$0.needsArticle }
            guard let answer = neighbors.randomElement(using: &rng) else { continue }
            let notNeighbors = atlas.countries.filter {
                $0.region == country.region && $0 != country && !country.borders.contains($0.code)
            }
            guard notNeighbors.count >= 3 else { continue }
            let choices = (Array(notNeighbors.shuffled(using: &rng).prefix(3)) + [answer]).shuffled(using: &rng)
            let countryName = country.name
            let answerName = answer.name
            return QuizQuestion(
                id: 0, kind: .borders, emoji: country.flag,
                prompt: String(localized: "Which of these countries borders \(countryName)?"),
                options: choices.map { .init(emoji: $0.flag, text: $0.name) },
                correctIndex: choices.firstIndex(of: answer)!,
                explanation: String(localized: "\(answerName) shares a border with \(countryName).")
            )
        }
        return nil
    }

    /// "Which of these countries has no coastline?"
    private func landlocked(rng: inout SeededGenerator) -> QuizQuestion? {
        guard let answer = atlas.countries.filter({ $0.isLandlocked && !$0.needsArticle }).randomElement(using: &rng) else { return nil }
        var pool = atlas.countries.filter { !$0.isLandlocked && $0.region == answer.region }
        if pool.count < 3 { pool = atlas.countries.filter { !$0.isLandlocked } }
        let choices = (Array(pool.shuffled(using: &rng).prefix(3)) + [answer]).shuffled(using: &rng)
        let answerName = answer.name
        return QuizQuestion(
            id: 0, kind: .landlocked, emoji: "🏖️",
            prompt: String(localized: "Which of these countries has no coastline?"),
            options: choices.map { .init(emoji: $0.flag, text: $0.name) },
            correctIndex: choices.firstIndex(of: answer)!,
            explanation: String(localized: "\(answerName) is landlocked: it has no coastline.")
        )
    }

    /// "Which of these countries is the largest?" Four from the same region, close in size.
    private func largestCountry(level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> QuizQuestion? {
        let ratio: ClosedRange<Double> = level == .hard ? 1.2...2 : 1.25...3.5
        let regions = Array(Set(atlas.countries.map(\.region))).sorted()
        for region in regions.shuffled(using: &rng) {
            let pool = atlas.countries.filter { $0.region == region && $0.area > 0 }
            var picks: [QuizAtlas.Country] = []
            for country in pool.shuffled(using: &rng) where picks.allSatisfy({
                ratio.contains(Double(max($0.area, country.area)) / Double(max(min($0.area, country.area), 1)))
            }) {
                picks.append(country)
                if picks.count == 4 { break }
            }
            guard picks.count == 4 else { continue }
            let answer = picks.max { $0.area < $1.area }!
            let summary = picks
                .sorted { $0.area > $1.area }
                .map { "\($0.name) \($0.area.formatted(.number.notation(.compactName))) km²" }
                .joined(separator: " · ")
            return QuizQuestion(
                id: 0, kind: .largestCountry, emoji: "📏",
                prompt: String(localized: "Which of these countries is the largest?"),
                options: picks.map { .init(emoji: $0.flag, text: $0.name) },
                correctIndex: picks.firstIndex(of: answer)!,
                explanation: summary
            )
        }
        return nil
    }

    // MARK: - Picking

    /// A well-known country for easy and medium questions, any other for hard ones.
    private func pickCountry(level: QuizQuestion.Difficulty, forCapital: Bool = false, rng: inout SeededGenerator) -> QuizAtlas.Country? {
        let pool = atlas.countries.filter {
            (level == .hard) != $0.isWellKnown && !$0.needsArticle && !(forCapital && $0.capitalGivesAway)
        }
        return pool.randomElement(using: &rng) ?? atlas.countries.randomElement(using: &rng)
    }

    /// Three other countries. Easy: other well-known ones from anywhere, so it's a fair guess.
    /// Otherwise from the same subregion when there are enough, which is harder.
    private func sameArea(as country: QuizAtlas.Country, level: QuizQuestion.Difficulty, rng: inout SeededGenerator) -> [QuizAtlas.Country] {
        if level == .easy {
            let pool = atlas.countries.filter { $0.isWellKnown && $0 != country && $0.region != country.region }
            if pool.count >= 3 { return Array(pool.shuffled(using: &rng).prefix(3)) }
        }
        var pool = atlas.countries.filter { $0.subregion == country.subregion && $0 != country }
        if pool.count < 3 { pool = atlas.countries.filter { $0.region == country.region && $0 != country } }
        if pool.count < 3 { pool = atlas.countries.filter { $0 != country } }
        return Array(pool.shuffled(using: &rng).prefix(3))
    }

    /// Four cities in four countries, every pair `apart` by an amount within `range`.
    private func pickCities(
        from pool: [QuizAtlas.City], rng: inout SeededGenerator,
        apart: (QuizAtlas.City, QuizAtlas.City) -> Double, in range: ClosedRange<Double>
    ) -> [QuizAtlas.City]? {
        var picks: [QuizAtlas.City] = []
        var countries = Set<String>()
        for city in pool.shuffled(using: &rng).prefix(400) where !countries.contains(city.countryCode) {
            guard picks.allSatisfy({ range.contains(apart($0, city)) }) else { continue }
            picks.append(city)
            countries.insert(city.countryCode)
            if picks.count == 4 { return picks }
        }
        return nil
    }

    /// "41°N" or "12°S".
    static func latitude(_ value: Double) -> String {
        let degrees = Int(abs(value).rounded())
        return value >= 0 ? String(localized: "\(degrees)°N") : String(localized: "\(degrees)°S")
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
