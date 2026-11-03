import SwiftUI
import WatchKit

/// Swipe sideways between My Location and the saved cities, like the iPhone app.
/// Each page scrolls down (or turn the Digital Crown) for the hourly, conditions and 10-day forecast.
struct WatchRootView: View {
    @Environment(LocationService.self) private var location
    @Environment(CityStore.self) private var cityStore

    @AppStorage("watch.selectedPlace") private var selectedID = Place.currentLocationID

    // Sent from the phone (see PhoneSync). Scenes and temperatures rebuild when they change.
    @AppStorage(SceneStyle.packKey, store: SharedStore.defaults) private var scenePack: ScenePack = .classic
    @AppStorage(SceneStyle.customEmojiKey, store: SharedStore.defaults) private var customEmoji = ""
    @AppStorage(SceneStyle.plusActiveKey, store: SharedStore.defaults) private var plusActive = false
    @AppStorage(StyleSync.genmojiVersionKey, store: SharedStore.defaults) private var genmojiVersion = 0
    @AppStorage(DisplaySettings.temperatureKey, store: SharedStore.defaults) private var temperature: TemperatureSetting = .automatic

    private var styleKey: String {
        let style = SceneStyle.styleKey(pack: scenePack.rawValue, customJSON: customEmoji, plus: plusActive)
        return "\(style)|\(genmojiVersion)|\(temperature.rawValue)"
    }

    private var places: [Place] {
        let cities = cityStore.cities.map(Place.city)
        // With location turned off, skip the My Location page if there are cities to show.
        if location.isDenied, !cities.isEmpty { return cities }
        return [.currentLocation] + cities
    }

    private var complicationKey: [String] {
        let coordinate = location.location.map { String(format: "%.2f,%.2f", $0.coordinate.latitude, $0.coordinate.longitude) }
        return [coordinate ?? "", location.placeName ?? ""] + cityStore.cities.map(\.id.uuidString)
    }

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(places, id: \.id) { place in
                WatchCityPage(place: place, isActive: place.id == selectedID)
                    .tag(place.id)
            }
        }
        .tabViewStyle(.page)
        .id(styleKey)
        .onChange(of: selectedID) { _, _ in
            WKInterfaceDevice.current().play(.click)
        }
        .onChange(of: complicationKey, initial: true) {
            // Tell the complications which place to show: My Location, or the first city.
            WidgetSync.updatePlaces(
                cities: cityStore.cities,
                currentLocation: location.location,
                currentName: location.placeName,
                hasPlus: true
            )
        }
        .onChange(of: places.map(\.id), initial: true) { _, ids in
            // The selected city was deleted (maybe on the phone): go back to the first page.
            if !ids.contains(selectedID), let first = ids.first {
                selectedID = first
            }
        }
    }
}
