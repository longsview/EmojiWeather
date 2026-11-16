import CoreLocation
import SwiftUI
import WidgetKit

/// The app's modes in a Liquid Glass tab bar (weather pages, the weather map, settings), with
/// Skymoji Daily as our own round glass button beside it. It isn't a tab, because it only opens
/// a sheet: iOS 27 draws a search-role tab as an ordinary fourth tab, so it's drawn by hand.
struct RootView: View {
    enum AppTab: Hashable { case weather, map, settings }

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

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The open iPhone Duo puts the tab bar down the right edge instead of along the bottom.
    private var hasSideTabBar: Bool {
        sizeClass == .regular && UIDevice.current.userInterfaceIdiom == .phone
    }

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
        .overlay(alignment: .bottomTrailing) {
            DailyQuizButton(hasPlayedToday: quiz.hasPlayedToday) { showingQuiz = true }
                .padding(.trailing, hasSideTabBar ? Self.sideBarInset : Self.bottomBarInset)
                .padding(.bottom, hasSideTabBar ? Self.sideBarBottom : Self.bottomBarBottom)
                .ignoresSafeArea(.container, edges: .bottom)
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


extension RootView {
    // Where the round button sits. Trailing follows the language direction, so it moves to the
    // left side in Arabic along with the tab bar.
    /// Phones: level with the floating tab bar, at its trailing end.
    static let bottomBarInset: CGFloat = 20
    static let bottomBarBottom: CGFloat = 26
    /// Open iPhone Duo: under the tab bar that runs down the right edge.
    static let sideBarInset: CGFloat = 20
    static let sideBarBottom: CGFloat = 26
}

/// Skymoji Daily's round glass button: an orange question bubble while today's quiz waits,
/// a check once it's done.
struct DailyQuizButton: View {
    let hasPlayedToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: hasPlayedToday ? "checkmark.bubble.fill" : "questionmark.bubble.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(hasPlayedToday ? Color.primary : Color.orange)
                .frame(width: 58, height: 58)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Daily"))
        .accessibilityHint(Text(hasPlayedToday ? "Today's quiz is done" : "Play today's quiz"))
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
