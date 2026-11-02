import SwiftUI

@main
struct EmojiWeatherApp: App {
    @State private var location = LocationService()
    @State private var cityStore = CityStore()
    @State private var weather = WeatherProvider()
    @State private var purchases = PurchaseManager()
    @State private var ads = AdsManager()

    /// Changes whenever the widgets' list of places or the Plus status changes.
    private var widgetKey: String {
        let coordinate = location.location.map {
            String(format: "%.2f,%.2f", $0.coordinate.latitude, $0.coordinate.longitude)
        } ?? "none"
        let cities = cityStore.cities.map { "\($0.id)\($0.name)" }.joined()
        return "\(coordinate)|\(location.placeName ?? "")|\(cities)|\(purchases.hasPlus)"
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(cityStore)
                .environment(weather)
                .environment(purchases)
                .environment(ads)
                // Normally the first weather starts ads; this covers no location and no cities.
                .task { await ads.start(after: .seconds(15)) }
                .task(id: widgetKey) {
                    WidgetSync.updatePlaces(
                        cities: cityStore.cities,
                        currentLocation: location.location,
                        currentName: location.placeName,
                        hasPlus: purchases.hasPlus
                    )
                }
        }
    }
}
