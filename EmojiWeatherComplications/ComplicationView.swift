import SwiftUI
import WidgetKit

struct ComplicationView: View {
    let entry: ComplicationEntry

    @Environment(\.widgetFamily) private var family

    private var emoji: String { entry.weather.map { $0.weatherScene.emoji(in: $0.skyMode) } ?? "🌤️" }
    private var temperature: String { entry.weather?.temperature.shortTemperature ?? "--" }
    private var name: String { entry.place?.name ?? String(localized: "Open Skymoji to add a place") }

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(verbatim: emoji).font(.system(size: 22))
                    Text(verbatim: temperature)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.7)
                }
            }

        case .accessoryCorner:
            Text(verbatim: emoji)
                .font(.system(size: 30))
                .widgetLabel {
                    Text(verbatim: "\(temperature) \(entry.place?.name ?? "")")
                }

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Text(verbatim: emoji).font(.system(size: 38))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(verbatim: temperature)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                    if let high = entry.weather?.high, let low = entry.weather?.low {
                        Text(verbatim: "↑\(high.shortTemperature) ↓\(low.shortTemperature)")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

        default:
            Text(verbatim: "\(emoji) \(temperature) \(entry.place?.name ?? "")")
        }
    }

    private var accessibilityText: String {
        guard let weather = entry.weather else { return name }
        return "\(name), \(weather.temperature.spokenTemperature), \(weather.condition)"
    }
}
