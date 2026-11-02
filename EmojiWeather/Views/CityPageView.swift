import CoreLocation
import os
import SwiftUI
import WeatherKit

private let logger = Logger(subsystem: "EmojiWeather", category: "Weather")

/// One full-screen page: the emoji scene with the city, temperature and a few key details.
/// Swiping up opens the full forecast.
struct CityPageView: View {
    let place: Place
    /// Only the visible page animates.
    let isActive: Bool
    /// True while something covers the whole page (the Places sheet), so the scene can pause.
    var isCovered = false
    var previewScene: WeatherScene?
    /// Tells the container which sky the visible page has, so its buttons can match.
    var onSkyChange: (SkyMode) -> Void = { _ in }

    @Environment(LocationService.self) private var location
    @Environment(WeatherProvider.self) private var weather
    @Environment(AdsManager.self) private var ads
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.scenePhase) private var scenePhase

    @State private var snapshot: WeatherSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingDetails = false
    @State private var showingPaywall = false

    private var targetLocation: CLLocation? {
        switch place {
        case .currentLocation: location.location
        case .city(let city): city.location
        }
    }

    private var timeZone: TimeZone {
        switch place {
        case .currentLocation: .current
        case .city(let city): city.timeZone
        }
    }

    private var placeName: String {
        switch place {
        case .currentLocation: location.placeName ?? "My Location"
        case .city(let city): city.name
        }
    }

    private var sceneConditions: SceneConditions {
        if let previewScene {
            let liveSky = snapshot.map { SkyMode(current: $0.current, today: $0.daily.first) }
            let sky = liveSky ?? (previewScene == .clearNight ? .night : .day)
            return SceneConditions(scene: previewScene, intensity: 0.8, windDrift: 0.3, sky: sky)
        }
        if let snapshot { return SceneConditions(current: snapshot.current, today: snapshot.daily.first) }
        return SceneConditions(scene: .cloudy)
    }

    /// Changes whenever the weather should be reloaded.
    private var loadKey: String {
        guard let target = targetLocation else { return "\(place.id)-none" }
        return String(format: "%@-%.2f,%.2f", place.id, target.coordinate.latitude, target.coordinate.longitude)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                EmojiSceneView(conditions: sceneConditions, paused: !isActive || isCovered)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: proxy.size.height * 0.47)
                    summary
                    Spacer(minLength: 12)
                    if showsBanner {
                        // Free tier: a small banner just above the Forecast hint on the first page.
                        BannerAdWithUpsell { showingPaywall = true }
                            .padding(.bottom, 14)
                    }
                    swipeHint
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 64)
                }
                .padding(.horizontal, 24)
            }
        }
        .environment(\.skyMode, sceneConditions.sky)
        .contentShape(Rectangle())
        .onChange(of: sceneConditions.sky, initial: true) { _, sky in
            if isActive { onSkyChange(sky) }
        }
        .onChange(of: isActive) { _, active in
            if active { onSkyChange(sceneConditions.sky) }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let isUpward = value.translation.height < -60
                    && abs(value.translation.height) > abs(value.translation.width) * 1.5
                if isUpward, snapshot != nil { showingDetails = true }
            }
        )
        .task(id: loadKey) { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Refresh when coming back to the app; the cache keeps this to one call per 30 minutes.
            if phase == .active, isActive { Task { await load() } }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingDetails) {
            if let snapshot {
                DetailsView(placeName: placeName, snapshot: snapshot, timeZone: timeZone) {
                    await load(forceRefresh: true)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white)
                .environment(\.colorScheme, .light)
                .presentationCornerRadius(36)
            }
        }
    }

    // MARK: - First page

    private var showsBanner: Bool {
        isCurrentLocation && ads.isReady && !purchases.hasPlus
    }

    private var isCurrentLocation: Bool {
        if case .currentLocation = place { return true }
        return false
    }

    @ViewBuilder
    private var summary: some View {
        if let current = snapshot?.current {
            WeatherSummaryView(
                placeName: placeName,
                showsLocationIcon: isCurrentLocation,
                timeZone: timeZone,
                temperature: current.temperature.shortTemperature,
                condition: current.condition.description,
                high: snapshot?.daily.first?.highTemperature.shortTemperature,
                low: snapshot?.daily.first?.lowTemperature.shortTemperature,
                tagline: sceneConditions.scene.tagline
            )
        } else {
            VStack(spacing: 16) {
                PlaceNameRow(placeName: placeName, showsLocationIcon: isCurrentLocation)
                status
            }
            .frame(maxWidth: .infinity)
            .readableOverEmoji()
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .currentLocation = place, !location.isAuthorized {
            LocationPermissionCard()
        } else if case .currentLocation = place, location.location == nil {
            if location.isLocating {
                ProgressView("Finding your location…")
            } else {
                retryMessage(location.failureMessage ?? "Waiting for your location…") {
                    location.refresh()
                }
            }
        } else if let errorMessage {
            retryMessage(errorMessage) {
                Task { await load(forceRefresh: true) }
            }
        } else if isLoading {
            ProgressView()
        }
    }

    private func retryMessage(_ message: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Try Again", action: action)
                .buttonStyle(.bordered)
                .tint(sceneConditions.sky.textColor)
        }
    }

    private var swipeHint: some View {
        Button {
            showingDetails = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "chevron.compact.up")
                    .font(.title2)
                Text("Forecast")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(sceneConditions.sky.textColor.opacity(0.55))
        }
        .opacity(snapshot == nil ? 0 : 1)
        .disabled(snapshot == nil)
    }

    // MARK: - Loading

    private func load(forceRefresh: Bool = false) async {
        guard let target = targetLocation else {
            snapshot = nil
            return
        }
        // Show cached weather right away, then fetch only if it's stale.
        if let cached = weather.cachedWeather(for: target) {
            snapshot = cached
            WidgetSync.save(cached, for: place)
            if !forceRefresh { return }
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await weather.weather(for: target, forceRefresh: forceRefresh)
            snapshot = fresh
            errorMessage = nil
            WidgetSync.save(fresh, for: place)
        } catch is CancellationError {
            // The page went away or the place changed; the next load takes over.
        } catch {
            logger.error("WeatherKit failed: \(String(describing: error), privacy: .public)")
            #if DEBUG
            // Usually WeatherKit isn't enabled for the App ID yet, or signing has no team.
            errorMessage = "Couldn't load the weather.\n\(error.localizedDescription)\nCheck that WeatherKit is enabled for this App ID (Capabilities and App Services)."
            #else
            errorMessage = "Couldn't load the weather."
            #endif
        }
    }
}
