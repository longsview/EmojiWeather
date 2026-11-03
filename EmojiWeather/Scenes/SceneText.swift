import SwiftUI

// Text helpers shared by the iPhone and Apple Watch apps.

/// The place's current time, so the pages double as a world clock. Cities in another time zone
/// also say how far ahead or behind they are.
struct LocalTimeView: View {
    let timeZone: TimeZone
    var font: Font = .system(.headline, design: .rounded, weight: .semibold)

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(context.date.formatted(DisplaySettings.timeStyle(timeZone)))
                    .monospacedDigit()
                if let offset = Self.offsetText(at: context.date, timeZone: timeZone) {
                    Text(offset)
                        .foregroundStyle(.secondary)
                }
            }
            .font(font)
            .contentTransition(.numericText())
        }
        .accessibilityLabel("Local time")
    }

    /// "3 hr ahead", "5½ hr behind", or nil for the device's own time zone.
    static func offsetText(at date: Date, timeZone: TimeZone) -> String? {
        let difference = timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard difference != 0 else { return nil }
        let hours = Double(abs(difference)) / 3600
        let whole = Int(hours)
        let fraction = hours - Double(whole)
        let amount: String
        switch fraction {
        case 0: amount = whole.formatted()
        case 0.5: amount = whole == 0 ? "½" : "\(whole.formatted())½"
        default: amount = hours.formatted(.number.precision(.fractionLength(0...2)))
        }
        return difference > 0 ? String(localized: "\(amount) hr ahead") : String(localized: "\(amount) hr behind")
    }
}

extension View {
    /// Text color for the current sky, plus a soft halo that keeps text readable where it
    /// overlaps falling emoji.
    func readableOverEmoji() -> some View {
        modifier(ReadableOverEmoji())
    }
}

private struct ReadableOverEmoji: ViewModifier {
    @Environment(\.skyMode) private var sky

    func body(content: Content) -> some View {
        content
            .foregroundStyle(sky.textColor)
            .shadow(color: sky.haloColor, radius: 8)
            .shadow(color: sky.haloColor, radius: 8)
    }
}
