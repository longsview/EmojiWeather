import SwiftUI

@main
struct EmojiWeatherApp: App {
    @State private var location = LocationService()
    @State private var cityStore = CityStore()
    @State private var weather = WeatherProvider()
    @State private var purchases = PurchaseManager()
    @State private var ads = AdsManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(location)
                .environment(cityStore)
                .environment(weather)
                .environment(purchases)
                .environment(ads)
                .task { await ads.start() }
        }
    }
}
