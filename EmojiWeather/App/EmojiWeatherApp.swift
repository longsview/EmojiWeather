import SwiftUI

@main
struct EmojiWeatherApp: App {
    @State private var location = LocationService()
    @State private var cityStore = CityStore()
    @State private var weather = WeatherProvider()
    @State private var purchases: PurchaseManager
    @State private var ads: AdsManager
    @State private var quiz: QuizStore

    /// Changes whenever the widgets' list of places or the Plus status changes.
    private var widgetKey: String {
        let coordinate = location.location.map {
            String(format: "%.2f,%.2f", $0.coordinate.latitude, $0.coordinate.longitude)
        } ?? "none"
        let cities = cityStore.cities.map { "\($0.id)\($0.name)" }.joined()
        return "\(coordinate)|\(location.placeName ?? "")|\(cities)|\(purchases.hasPlus)"
    }

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Crash reporting first, before anything touches the Google ads SDK, so Crashlytics
        // gets the crash handlers.
        CrashReporting.start()
        AppAnalytics.start()
        AdsManager.disableSDKCrashReporting()
        let purchases = PurchaseManager()
        #if DEBUG
        if ScreenshotMode.plus { purchases.debugUnlock = true }
        if ScreenshotMode.isActive { SceneStyle.chosenPack = ScreenshotMode.pack ?? .classic }
        #endif
        _purchases = State(initialValue: purchases)
        _ads = State(initialValue: AdsManager())
        let quiz = QuizStore()
        _quiz = State(initialValue: quiz)
        // Tapping a morning reminder opens the quiz.
        NotificationRouter.shared.quiz = quiz
        NotificationRouter.shared.start()
        // Keeps the watch's scenes, units and clock in step with the phone.
        WatchSync.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(cityStore)
                .environment(weather)
                .environment(purchases)
                .environment(ads)
                .environment(quiz)
                // Normally the first weather starts ads; this covers no location and no cities.
                .task { await ads.start(after: .seconds(15)) }
                .task(id: purchases.hasPlus) {
                    AppAnalytics.updateUserProperties(hasPlus: purchases.hasPlus)
                }
                .task(id: widgetKey) {
                    WidgetSync.updatePlaces(
                        cities: cityStore.cities,
                        currentLocation: location.location,
                        currentName: location.placeName,
                        hasPlus: purchases.hasPlus
                    )
                }
        }
        // Watch for big moves (about 1 km) while the app is open, and get a fresh fix each
        // time it comes back, so the current-location page follows you when you travel.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: location.startUpdating()
            case .background:
                location.stopUpdating()
                // Refresh the next mornings' reminders with the latest forecast.
                Task { await QuizStore.scheduleReminders() }
            default: break
            }
        }
    }
}
