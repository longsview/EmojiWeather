import SwiftUI

/// The Apple Watch app: the same emoji scenes and synced cities as the iPhone app.
/// The watch fetches its own weather with WeatherKit and reads the city list from iCloud,
/// so it works on its own without the phone nearby.
@main
struct EmojiWeatherWatchApp: App {
    @State private var location = LocationService()
    @State private var cityStore = CityStore()
    @State private var weather = WeatherProvider()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(location)
                .environment(cityStore)
                .environment(weather)
                .environment(\.locale, DisplaySettings.locale)
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
