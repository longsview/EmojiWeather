import CoreLocation
import SwiftUI

/// The app's two modes in a Liquid Glass tab bar: the emoji weather pages and the weather map.
struct RootView: View {
    enum AppTab: Hashable { case weather, map, settings }

    @State private var tab: AppTab = .weather

    // Read here so changing a unit or the clock redraws every screen.
    @AppStorage(DisplaySettings.temperatureKey, store: SharedStore.defaults)
    private var temperature: TemperatureSetting = .automatic
    @AppStorage(DisplaySettings.clockKey, store: SharedStore.defaults)
    private var clock: ClockSetting = .automatic

    // Scene packs and custom emoji change how every scene looks.
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage(SceneStyle.packKey, store: SharedStore.defaults)
    private var scenePack: ScenePack = .classic
    @AppStorage(SceneStyle.customEmojiKey, store: SharedStore.defaults)
    private var customEmoji = ""

    private var displayKey: String {
        let style = SceneStyle.styleKey(pack: scenePack.rawValue, customJSON: customEmoji, plus: purchases.hasPlus)
        return "\(temperature.rawValue)-\(clock.rawValue)-\(style)"
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Weather", systemImage: "sun.max.fill", value: AppTab.weather) {
                HomeView(isVisible: tab == .weather)
                    .id(displayKey)
            }
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapTab()
                    .id(displayKey)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.never)
        // Times everywhere follow the 12/24-hour choice.
        .environment(\.locale, DisplaySettings.locale)
    }
}

/// The map, or a Skymoji+ teaser for free users in Release builds.
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
                    .accessibilityHidden(true)
                Text("Skymoji Map")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                Text("See storms, sun and temperatures across the map, like the old TV weather.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showingPaywall = true
                } label: {
                    Text("Unlock with Skymoji+")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.black)
                .controlSize(.large)
                .padding(.top, 6)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(reason: String(localized: "The emoji weather map is part of Skymoji+."))
            }
        }
    }
}
