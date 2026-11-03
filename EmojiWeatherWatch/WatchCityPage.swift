import CoreLocation
import os
import SwiftUI
import WatchKit
import WeatherKit

/// One place: the emoji scene fills the screen behind the weather, and the forecast scrolls up
/// over it, like the iPhone app's main page and forecast sheet in one.
struct WatchCityPage: View {
    let place: Place
    /// Only the page on screen animates and loads.
    let isActive: Bool

    @Environment(LocationService.self) private var location
    @Environment(WeatherProvider.self) private var weather
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var snapshot: WeatherSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let logger = Logger(subsystem: "EmojiWeatherWatch", category: "Weather")

    private var targetLocation: CLLocation? {
        switch place {
        case .currentLocation: location.location
        case .city(let city): city.location
        }
    }

    private var placeName: String {
        switch place {
        case .currentLocation: location.placeName ?? String(localized: "My Location")
        case .city(let city): city.name
        }
    }

    private var timeZone: TimeZone {
        switch place {
        case .currentLocation: .current
        case .city(let city): city.timeZone
        }
    }

    private var conditions: SceneConditions {
        if let snapshot { return SceneConditions(current: snapshot.current, today: snapshot.daily.first) }
        return SceneConditions(scene: .cloudy)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchHeroView(
                    placeName: placeName,
                    showsLocationIcon: place == .currentLocation,
                    timeZone: timeZone,
                    snapshot: snapshot,
                    tagline: conditions.scene.tagline
                )
                .containerRelativeFrame(.vertical, alignment: .bottom)

                if let snapshot {
                    WatchHourlySection(hours: snapshot.hourly, timeZone: timeZone)
                    WatchConditionsSection(current: snapshot.current, today: snapshot.daily.first, timeZone: timeZone)
                    WatchDailySection(days: snapshot.daily, timeZone: timeZone)
                    WatchAttributionView()
                } else {
                    status
                }
            }
            .padding(.horizontal, 4)
        }
        .environment(\.skyMode, conditions.sky)
        .containerBackground(for: .tabView) {
            // Fixed behind the page (it doesn't scroll), and it fades between cities on a swipe.
            GeometryReader { proxy in
                EmojiSceneView(
                    conditions: conditions,
                    paused: !isActive || isLuminanceReduced,
                    canvasScale: proxy.size.width / 360
                )
            }
            .ignoresSafeArea()
            .overlay {
                // Dim the scene while the screen is in always-on mode.
                if isLuminanceReduced { Color.black.opacity(0.5) }
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            // Swiping back to My Location asks for a fresh fix, in case the watch has moved.
            if active, place == .currentLocation { location.refresh() }
        }
        .task(id: TaskKey(isActive: isActive, location: targetLocation)) {
            guard isActive else { return }
            await load()
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var status: some View {
        Group {
            if place == .currentLocation, !location.isAuthorized {
                if location.isDenied {
                    Text("Location access is off. Turn it on in Settings > Privacy & Security > Location Services.")
                } else {
                    Button("Allow Location") { location.requestPermission() }
                        .buttonStyle(.borderedProminent)
                }
            } else if let errorMessage {
                VStack(spacing: 6) {
                    Text(errorMessage)
                    Button("Try Again") { Task { await load(forceRefresh: true) } }
                }
            } else if let failure = location.failureMessage, place == .currentLocation {
                Text(failure)
            } else if place == .currentLocation, location.location == nil {
                VStack(spacing: 6) {
                    ProgressView()
                    Text("Finding your location…")
                }
            } else {
                ProgressView()
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .readableOverEmoji()
    }

    // MARK: - Loading

    private func load(forceRefresh: Bool = false) async {
        guard let target = targetLocation else { return }
        if let cached = weather.cachedWeather(for: target) {
            snapshot = cached
            if !forceRefresh { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let isFirstLoad = snapshot == nil
            snapshot = try await weather.weather(for: target, forceRefresh: forceRefresh)
            errorMessage = nil
            // A light tap when the weather first lands.
            if isFirstLoad { WKInterfaceDevice.current().play(.success) }
        } catch is CancellationError {
        } catch {
            logger.error("WeatherKit failed: \(String(describing: error), privacy: .public)")
            if snapshot == nil {
                #if DEBUG
                // Usually WeatherKit isn't on for the watch App ID yet, or signing has no team.
                errorMessage = "Couldn't load the weather.\n\(error.localizedDescription)"
                #else
                errorMessage = String(localized: "Couldn't load the weather.")
                #endif
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private struct TaskKey: Equatable {
        let isActive: Bool
        let location: CLLocation?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.isActive == rhs.isActive && lhs.location?.coordinate.latitude == rhs.location?.coordinate.latitude
                && lhs.location?.coordinate.longitude == rhs.location?.coordinate.longitude
        }
    }
}

/// The first screen: city, local time, big temperature, condition and high/low.
private struct WatchHeroView: View {
    let placeName: String
    let showsLocationIcon: Bool
    let timeZone: TimeZone
    let snapshot: WeatherSnapshot?
    let tagline: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                if showsLocationIcon {
                    Image(systemName: "location.fill").font(.caption2)
                }
                Text(placeName).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(.headline, design: .rounded, weight: .bold))

            // The watch face already shows the time here, so only cities in another time zone
            // get a world-clock line.
            if timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT() {
                LocalTimeView(timeZone: timeZone, font: .system(.caption, design: .rounded, weight: .semibold))
            }

            if let snapshot {
                let today = snapshot.daily.first
                Text(snapshot.current.temperature.shortTemperature)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(snapshot.current.condition.description)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                if let today {
                    HStack(spacing: 8) {
                        Text(verbatim: "↑\(today.highTemperature.shortTemperature)")
                        Text(verbatim: "↓\(today.lowTemperature.shortTemperature)")
                    }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .readableOverEmoji()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [placeName, Date.now.formatted(DisplaySettings.timeStyle(timeZone))]
        if let snapshot {
            parts.append(snapshot.current.temperature.spokenTemperature)
            parts.append(snapshot.current.condition.description)
            if let today = snapshot.daily.first {
                parts.append(String(localized: "High \(today.highTemperature.spokenTemperature)"))
                parts.append(String(localized: "Low \(today.lowTemperature.spokenTemperature)"))
            }
            parts.append(tagline)
        }
        return parts.joined(separator: ", ")
    }
}
