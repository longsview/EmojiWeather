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
                    .modifier(RoomForTabBar(side: hasSideTabBar))
            }
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapTab()
                    .id(displayKey)
                    .modifier(RoomForTabBar(side: hasSideTabBar))
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
                    .modifier(RoomForTabBar(side: hasSideTabBar))
            }
        }
        // The system tab bar is hidden and drawn by hand, so the quiz's round button can sit
        // beside it on every iPhone width (the system bar stays centred and leaves no room on
        // 390-point phones). Each tab makes room for it with RoomForTabBar, because TabView
        // doesn't pass an outer safe-area inset down to its tabs.
        .overlay(alignment: hasSideTabBar ? .trailing : .bottom) {
            navigationBar(vertical: hasSideTabBar)
        }
        .sheet(isPresented: $showingQuiz) {
            QuizView()
        }
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
    /// The glass tab bar and the quiz's round button: side by side along the bottom on phones,
    /// stacked down the right edge (left in right-to-left languages) on the open iPhone Duo.
    @ViewBuilder
    func navigationBar(vertical: Bool) -> some View {
        let quizButton = DailyQuizButton(hasPlayedToday: quiz.hasPlayedToday) { showingQuiz = true }
        GlassEffectContainer(spacing: 12) {
            if vertical {
                VStack(spacing: 12) {
                    GlassTabBar(selection: $tab, vertical: true)
                    quizButton
                }
                .padding(.trailing, 12)
            } else {
                HStack(spacing: 10) {
                    GlassTabBar(selection: $tab, vertical: false)
                    quizButton
                }
                .padding(.horizontal, 16)
                // Down into the home-indicator area, where the system tab bar sits (about
                // 21 points from the bottom edge).
                .offset(y: 16)
            }
        }
    }
}

/// Hides the system tab bar and keeps a tab's content clear of the hand-drawn one: bottom
/// padding on phones, trailing padding on the open iPhone Duo.
struct RoomForTabBar: ViewModifier {
    let side: Bool

    /// How far content keeps clear: along the bottom, the 60-point capsule sits partly in the
    /// home-indicator area, so less is needed than down the side.
    static let bottomRoom: CGFloat = 52
    static let sideRoom: CGFloat = 84

    // Clear spacers rather than safeAreaPadding: Lists (Settings) ignore safe-area padding but
    // honour insets.
    func body(content: Content) -> some View {
        content
            .toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !side { Color.clear.frame(height: Self.bottomRoom).allowsHitTesting(false) }
            }
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if side { Color.clear.frame(width: Self.sideRoom).allowsHitTesting(false) }
            }
    }
}

/// RoomForTabBar for a List or Form inside a NavigationStack, which doesn't see the tab's
/// insets: content margins on the scrolling content instead.
struct ListRoomForTabBar: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The open Duo's status-bar column, when it's on the bar's side: the bar sits inside it,
    /// but the Form's margins are measured from the screen edge.
    @State private var trailingSafeArea: CGFloat = 0

    func body(content: Content) -> some View {
        // Only the bar's edge is changed, so the Form keeps its usual margins elsewhere.
        if sizeClass == .regular && UIDevice.current.userInterfaceIdiom == .phone {
            content
                // Plus a little extra when the status-bar column is on this side, to match the gap
                // on the other side (right-to-left).
                .contentMargins(.trailing, RoomForTabBar.sideRoom + (trailingSafeArea > 0 ? trailingSafeArea + 21 : 0), for: .scrollContent)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { trailingSafeArea = $0 }
        } else {
            content.contentMargins(.bottom, RoomForTabBar.bottomRoom + 16, for: .scrollContent)
        }
    }
}

/// Weather, Map and Settings in one Liquid Glass capsule, like the system tab bar.
struct GlassTabBar: View {
    @Binding var selection: RootView.AppTab
    let vertical: Bool

    private struct Item {
        let tab: RootView.AppTab
        let title: LocalizedStringKey
        let symbol: String
    }

    private let items = [
        Item(tab: .weather, title: "Weather", symbol: "sun.max.fill"),
        Item(tab: .map, title: "Map", symbol: "map.fill"),
        Item(tab: .settings, title: "Settings", symbol: "gearshape.fill"),
    ]

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(items, id: \.tab) { item in
                Button {
                    selection = item.tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 24)
                        Text(item.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selection == item.tab ? Color.accentColor : Color.primary)
                    .frame(width: 72, height: 52)
                    .background {
                        if selection == item.tab {
                            Capsule().fill(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item.tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .sensoryFeedback(.selection, trigger: selection)
    }
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
                .frame(width: 60, height: 60)
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
