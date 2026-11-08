import SwiftUI
import WidgetKit

/// The Skymoji Daily streak: free for everyone, since it brings people back each day.
/// Tapping it opens the quiz.
struct DailyQuizWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: QuizStats.widgetKind, provider: DailyQuizProvider()) { entry in
            DailyQuizWidgetView(entry: entry)
                .widgetURL(URL(string: "skymoji://daily"))
        }
        .configurationDisplayName("Skymoji Daily")
        .description("Your quiz streak, and whether today's quiz is done.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DailyQuizEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let playedToday: Bool
}

struct DailyQuizProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyQuizEntry {
        DailyQuizEntry(date: .now, streak: 5, playedToday: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyQuizEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyQuizEntry>) -> Void) {
        // Now, then again just after midnight when a new quiz is ready (and a streak can lapse).
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry(at: .now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> DailyQuizEntry {
        let stats = QuizStats.load()
        return DailyQuizEntry(date: date, streak: stats.activeStreak(asOf: date), playedToday: stats.hasPlayed(on: date))
    }
}

struct DailyQuizWidgetView: View {
    let entry: DailyQuizEntry

    @Environment(\.widgetFamily) private var family

    private var status: String {
        entry.playedToday ? String(localized: "Done for today ✅") : String(localized: "Today's quiz is ready")
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall {
                    LinearGradient(colors: [Color(hex: 0xFFF6D6), .white], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.clear
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Skymoji Daily, \(status), \(String(localized: "\(entry.streak)-day streak"))"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(verbatim: entry.playedToday ? "🔥" : "🧩").font(.system(size: 20))
                    Text(verbatim: "\(entry.streak)")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "🧩 Skymoji Daily")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .widgetAccentable()
                Text(verbatim: "🔥 \(entry.streak)")
                    .font(.system(.body, design: .rounded, weight: .heavy))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(verbatim: "🧩 🔥\(entry.streak) · \(status)")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.playedToday ? "✅" : "🧩").font(.system(size: 40))
                Spacer(minLength: 0)
                Text(verbatim: "🔥 \(entry.streak)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text(String(localized: "\(entry.streak)-day streak"))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(status)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
