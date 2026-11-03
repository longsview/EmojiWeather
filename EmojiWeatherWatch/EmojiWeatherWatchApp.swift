import SwiftUI

/// The Apple Watch app: the same emoji scenes and synced cities as the iPhone app.
/// The watch fetches its own weather with WeatherKit and reads the city list from iCloud,
/// so it works on its own without the phone nearby.
@main
struct EmojiWeatherWatchApp: App {
    @State private var location = LocationService()
    @State private var cityStore = CityStore()
    @State private var weather = WeatherProvider()

    // Sent from the phone. Read here so a new clock choice reaches every screen.
    @AppStorage(DisplaySettings.clockKey, store: SharedStore.defaults)
    private var clock: ClockSetting = .automatic

    @Environment(\.scenePhase) private var scenePhase

    init() {
        CrashReporting.start()
        // Scene pack, your own emoji and Genmoji, units and clock come from the phone.
        PhoneSync.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(location)
                .environment(cityStore)
                .environment(weather)
                .environment(\.locale, DisplaySettings.locale)
                .id(clock)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Fresh fix on every raise, and follow big moves while the app is open.
                    if phase == .active {
                        location.startUpdating()
                    } else {
                        location.stopUpdating()
                    }
                }
        }
    }
}
