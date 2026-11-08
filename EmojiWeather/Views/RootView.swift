import CoreLocation
import SwiftUI
import WidgetKit

/// The app's modes in a Liquid Glass tab bar (weather pages, the weather map, settings), with
/// Skymoji Daily as a separate round button beside it.
struct RootView: View {
    enum AppTab: Hashable { case weather, map, settings, daily }

    @State private var tab: AppTab = {
        #if DEBUG
        switch ScreenshotMode.tab {
        case "map": return .map
        case "settings": return .settings
        default:
            if ["paywall", "scenePack"].contains(ScreenshotMode.open) { return .settings }
        }
        #endif
        return .weather
    }()

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

    @Environment(QuizStore.self) private var quiz
    /// Skymoji Daily opens as a sheet over whichever tab is showing.
    @State private var showingQuiz = false

    /// An orange question bubble while today's quiz waits; once it's done, a check bubble in the
    /// same color as the other tab icons. Tab bars tint every icon alike, so the orange is
    /// baked into the image.
    private var dailyIcon: Image {
        guard !quiz.hasPlayedToday else { return Image(systemName: "checkmark.bubble.fill") }
        let name = "questionmark.bubble.fill"
        guard let symbol = UIImage(systemName: name) else { return Image(systemName: name) }
        return Image(uiImage: symbol.withTintColor(.systemOrange, renderingMode: .alwaysOriginal))
    }

    /// Picking the Daily button opens the quiz instead of switching tabs.
    private var selection: Binding<AppTab> {
        Binding(
            get: { tab },
            set: { newTab in
                if newTab == .daily {
                    showingQuiz = true
                } else {
                    tab = newTab
                }
            }
        )
    }

    private var displayKey: String {
        let style = SceneStyle.styleKey(pack: scenePack.rawValue, customJSON: customEmoji, plus: purchases.hasPlus)
        return "\(temperature.rawValue)-\(clock.rawValue)-\(style)"
    }

    var body: some View {
        TabView(selection: selection) {
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
            // The search role puts it in its own glass button beside the tab bar, like a
            // compose button: an action, not a place.
            Tab(value: AppTab.daily, role: .search) {
                Color.clear
            } label: {
                Label {
                    Text("Daily")
                } icon: {
                    dailyIcon
                }
            }
        }
        .sheet(isPresented: $showingQuiz) {
            QuizView()
        }
        .tabBarMinimizeBehavior(.never)
        .onChange(of: tab) { _, newTab in
            if newTab == .map { AppAnalytics.log(.mapOpened) }
        }
        .onChange(of: displayKey) {
            // Widgets and the watch follow units, the clock, the scene pack and your own emoji.
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.send()
        }
        // Times everywhere follow the 12/24-hour choice.
        .environment(\.locale, DisplaySettings.locale)
    }
}

/// The map, or a Skymoji+ teaser for free users.
private struct MapTab: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(CityStore.self) private var cityStore
    @Environment(LocationService.self) private var location

    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID
    @State private var showingPaywall = false

    /// Plus only, in Debug too, so the paywall can be tested. The debug menu's unlock and
    /// -SkymojiPlus open it without buying.
    private var isUnlocked: Bool { purchases.hasPlus }

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
