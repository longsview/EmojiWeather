import CoreLocation
import Foundation
import Observation
import UserNotifications
import WidgetKit

/// The daily quiz's state: today's questions, streaks and the "guess tomorrow's high" game.
/// Everything stays on the device. Streak numbers also go to the App Group for the widget.
@MainActor
@Observable
final class QuizStore {
    private(set) var quiz: DailyQuiz?
    private(set) var isBuilding = false
    private(set) var stats: QuizStats
    /// Yesterday's guess, scored, waiting to be shown once.
    private(set) var guessResult: GuessResult?
    /// Today's guess for tomorrow, once locked in.
    private(set) var pendingGuess: HighGuess?

    @ObservationIgnored private var atlas: QuizAtlas?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let quizKey = "quiz.today.v1"
    private static let guessKey = "quiz.guess.v1"
    /// Day 1 of Skymoji Daily.
    private static let firstDay = DateComponents(calendar: .current, year: 2026, month: 11, day: 1)

    init() {
        stats = QuizStats.load()
        quiz = Self.decode(DailyQuiz.self, defaults.data(forKey: Self.quizKey))
        pendingGuess = Self.decode(HighGuess.self, defaults.data(forKey: Self.guessKey))
    }

    static var today: String { dayString(for: .now) }

    static func dayString(for date: Date) -> String { QuizStats.dayString(for: date) }

    static var todayNumber: Int {
        let start = Calendar.current.date(from: firstDay) ?? .now
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return max(days + 1, 1)
    }

    var hasPlayedToday: Bool { quiz?.day == Self.today && quiz?.isFinished == true }

    /// The streak as of today: a streak whose last day was before yesterday has ended.
    var currentStreak: Int { stats.activeStreak() }

    // MARK: - Today's quiz

    /// Loads today's quiz, building it if there isn't one for today yet.
    func prepare(origin: CLLocation?, weather: WeatherProvider) async {
        if quiz?.day != Self.today {
            quiz = nil
        }
        await scoreYesterdaysGuess(weather: weather)
        guard quiz == nil, !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }
        if atlas == nil { atlas = await QuizAtlas.load() }
        guard let atlas else { return }
        let built = await QuizBuilder(atlas: atlas, weather: weather, origin: origin, day: Self.today, number: Self.todayNumber).build()
        quiz = built
        save()
    }

    func answer(_ questionID: Int, with optionIndex: Int) {
        guard var quiz, let index = quiz.questions.firstIndex(where: { $0.id == questionID }),
              !quiz.questions[index].isAnswered else { return }
        quiz.questions[index].chosenIndex = optionIndex
        self.quiz = quiz
        if quiz.isFinished { finish(quiz) }
        save()
    }

    private func finish(_ quiz: DailyQuiz) {
        guard stats.lastPlayedDay != quiz.day else { return }
        let yesterday = Self.dayString(for: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        stats.streak = stats.lastPlayedDay == yesterday ? stats.streak + 1 : 1
        stats.bestStreak = max(stats.bestStreak, stats.streak)
        stats.played += 1
        stats.correct += quiz.score
        if quiz.score == quiz.questions.count { stats.perfectDays += 1 }
        stats.lastPlayedDay = quiz.day
        stats.save()
        WidgetCenter.shared.reloadTimelines(ofKind: QuizStats.widgetKind)
    }

    /// The text people paste into Messages:
    /// "Skymoji Daily #12 ☀️☀️🌧️☀️☀️ 4/5 🔥 6"
    var shareText: String {
        guard let quiz else { return "" }
        var text = "Skymoji Daily #\(quiz.number) \(quiz.grid) \(quiz.score)/\(quiz.questions.count)"
        if currentStreak > 1 { text += " 🔥 \(currentStreak)" }
        return text
    }

    // MARK: - Guess tomorrow's high

    func lockInGuess(_ guess: Measurement<UnitTemperature>, placeName: String, location: CLLocation) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let saved = HighGuess(
            targetDay: Self.dayString(for: tomorrow),
            celsius: guess.converted(to: .celsius).value,
            placeName: placeName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        pendingGuess = saved
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.guessKey)
    }

    var hasGuessForTomorrow: Bool {
        guard let pendingGuess else { return false }
        return pendingGuess.targetDay > Self.today
    }

    func dismissGuessResult() { guessResult = nil }

    /// On the target day (or later), compares the guess with that day's forecast high.
    private func scoreYesterdaysGuess(weather: WeatherProvider) async {
        guard let guess = pendingGuess, guess.targetDay <= Self.today else { return }
        defer {
            pendingGuess = nil
            defaults.removeObject(forKey: Self.guessKey)
        }
        // Too old to score fairly (the app wasn't opened on the day).
        guard guess.targetDay == Self.today,
              let snapshot = try? await weather.weather(for: CLLocation(latitude: guess.latitude, longitude: guess.longitude)),
              let high = snapshot.daily.first?.highTemperature else { return }
        let result = GuessResult(guess: guess, actualCelsius: high.converted(to: .celsius).value)
        guessResult = result
        stats.guesses += 1
        if result.isBullseye { stats.bullseyes += 1 }
        stats.save()
    }

    // MARK: - Morning reminder

    static let reminderID = "skymoji.daily.reminder"

    /// Asks for permission the first time, then repeats every morning at 8.
    func setReminder(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        guard enabled else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Skymoji Daily 🧩")
        content.body = String(localized: "Today's quiz is ready. Keep your 🔥 streak going!")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 8, minute: 0), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
        return true
    }

    // MARK: - Saving

    private func save() {
        defaults.set(try? JSONEncoder().encode(quiz), forKey: Self.quizKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// A guess at a place's high for a future day.
struct HighGuess: Codable, Hashable {
    var targetDay: String
    var celsius: Double
    var placeName: String
    var latitude: Double
    var longitude: Double
}

struct GuessResult: Hashable {
    let guess: HighGuess
    let actualCelsius: Double

    var errorDegrees: Double {
        let unit = DisplaySettings.temperatureUnit
        let guessValue = Measurement(value: guess.celsius, unit: UnitTemperature.celsius).converted(to: unit).value
        let actualValue = Measurement(value: actualCelsius, unit: UnitTemperature.celsius).converted(to: unit).value
        return abs(guessValue.rounded() - actualValue.rounded())
    }

    var isBullseye: Bool { errorDegrees < 1 }

    var emoji: String {
        switch errorDegrees {
        case ..<1: "🎯"
        case ..<3: "🔥"
        case ..<6: "👍"
        default: "🙈"
        }
    }
}
