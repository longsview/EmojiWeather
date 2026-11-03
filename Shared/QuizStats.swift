import Foundation

/// Lifetime numbers, kept in the App Group so the streak widget can show them.
struct QuizStats: Codable, Hashable {
    static let widgetKind = "SkymojiDailyWidget"
    private static let key = "quiz.stats.v1"

    var streak = 0
    var bestStreak = 0
    var played = 0
    var correct = 0
    var perfectDays = 0
    var lastPlayedDay: String?
    var guesses = 0
    var bullseyes = 0

    static func load() -> QuizStats {
        guard let data = SharedStore.defaults.data(forKey: key),
              let stats = try? JSONDecoder().decode(QuizStats.self, from: data) else { return QuizStats() }
        return stats
    }

    func save() {
        SharedStore.defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    /// "2026-11-03" in the user's calendar.
    static func dayString(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The streak as of `date`: a streak whose last day was before yesterday has ended.
    func activeStreak(asOf date: Date = .now) -> Int {
        guard let lastPlayedDay else { return 0 }
        let today = Self.dayString(for: date)
        let yesterday = Self.dayString(for: Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date)
        return lastPlayedDay == today || lastPlayedDay == yesterday ? streak : 0
    }

    func hasPlayed(on date: Date = .now) -> Bool { lastPlayedDay == Self.dayString(for: date) }
}
