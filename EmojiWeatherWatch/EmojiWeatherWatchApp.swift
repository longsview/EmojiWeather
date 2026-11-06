import SwiftUI
import WidgetKit

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
        #if DEBUG
        Self.seedComplicationsForScreenshots()
        #endif
    }

    #if DEBUG
    /// With -SkymojiScene, saves that scene's sample weather where the complications read it, so a
    /// watch face shows Skymoji data in screenshots without a location or a synced phone.
    private static func seedComplicationsForScreenshots() {
        guard let scene = ScreenshotMode.scene else { return }
        let fahrenheit = { (value: Double) in Measurement(value: value, unit: UnitTemperature.fahrenheit) }
        let place = WidgetPlace(
            id: WidgetPlace.currentLocationID,
            name: ScreenshotMode.place ?? "Cupertino",
            latitude: 37.32,
            longitude: -122.03
        )
        SharedStore.places = [place]
        SharedStore.setWeather(
            WidgetWeather(
                temperature: fahrenheit(scene.sampleFahrenheit),
                high: fahrenheit(scene.sampleHighFahrenheit),
                low: fahrenheit(scene.sampleLowFahrenheit),
                condition: scene.sampleCondition.description,
                scene: scene,
                sky: ScreenshotMode.sky ?? (scene == .clearNight ? .night : .day),
                hours: [],
                fetchedAt: .now
            ),
            for: place.id
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

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
