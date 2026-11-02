import CoreLocation
import SwiftUI

/// The app's two modes in a Liquid Glass tab bar: the emoji weather pages and the weather map.
struct RootView: View {
    enum AppTab: Hashable { case weather, map }

    @State private var tab: AppTab = .weather

    var body: some View {
        TabView(selection: $tab) {
            Tab("Weather", systemImage: "sun.max.fill", value: AppTab.weather) {
                HomeView(isVisible: tab == .weather)
            }
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapTab()
            }
        }
        .tabBarMinimizeBehavior(.never)
    }
}

/// The map, or an EmojiWeather+ teaser for free users in Release builds.
private struct MapTab: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(CityStore.self) private var cityStore
    @Environment(LocationService.self) private var location

    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID
    @State private var showingPaywall = false

    /// Plus only in Release; open to everyone in Debug for testing.
    private var isUnlocked: Bool {
        #if DEBUG
        true
        #else
        purchases.hasPlus
        #endif
    }

    /// Starts the map on the place the Weather tab is showing.
    private var center: CLLocationCoordinate2D? {
        switch Place.resolve(id: selectedPlaceID, cities: cityStore.cities) {
        case .currentLocation: location.location?.coordinate
        case .city(let city): city.location.coordinate
        }
    }

    var body: some View {
        if isUnlocked {
            WeatherMapView(center: center)
        } else {
            VStack(spacing: 14) {
                Text("🗺️⛈️☀️")
                    .font(.system(size: 56))
                Text("Emoji Weather Map")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                Text("See storms, sun and temperatures across the map, like the old TV weather.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showingPaywall = true
                } label: {
                    Text("Unlock with EmojiWeather+")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.black)
                .controlSize(.large)
                .padding(.top, 6)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(reason: "The emoji weather map is part of EmojiWeather+.")
            }
        }
    }
}
