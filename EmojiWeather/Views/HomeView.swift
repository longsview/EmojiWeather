import SwiftUI

/// iPhone: full-screen pages, one per place; swipe left and right between them.
/// iPad (regular width): a split view with the places list on the left and the city on the right.
struct HomeView: View {
    /// False while the Map tab is showing, so the scene can pause.
    var isVisible = true

    @Environment(CityStore.self) private var cityStore
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AdsManager.self) private var ads
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Per device on purpose: each device remembers which place it was last showing.
    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID

    @State private var showingPlaces = false
    /// Height covered by the tab bar and home indicator, so the bottom controls sit above it.
    @State private var bottomInset: CGFloat = 0
    @State private var previewScene: WeatherScene?
    @State private var showingGallery = false
    /// The visible page's scene. On iPhone it's drawn once behind all pages, so swiping
    /// slides only the text while the scene cross-fades.
    @State private var activeScene = SceneConditions(scene: .cloudy)
    private var activeSky: SkyMode { activeScene.sky }
    /// iPad: keep the places list and the city side by side.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if DEBUG
    @AppStorage(AdsManager.debugAdsEnabledKey) private var debugAdsEnabled = false
    #endif

    private var places: [Place] {
        [.currentLocation] + cityStore.cities.map { Place.city($0) }
    }

    /// The selected place, falling back to the current location if that city was deleted.
    private var currentPlace: Place {
        Place.resolve(id: selectedPlaceID, cities: cityStore.cities)
    }

    private var currentID: String { currentPlace.id }

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                pager
            }
        }
        .preferredColorScheme(activeSky.isDark ? .dark : .light)
        .sheet(isPresented: $showingPlaces) {
            PlacesView(selectedPlaceID: $selectedPlaceID)
        }

        #if DEBUG
        .fullScreenCover(isPresented: $showingGallery) {
            SceneGalleryView()
        }
        #endif
    }

    // MARK: - iPhone

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(places, id: \.id) { place in
                    CityPageView(
                        place: place,
                        isActive: place.id == currentID,
                        isCovered: isSceneCovered,
                        previewScene: previewScene,
                        showsScene: false,
                        bottomInset: bottomInset,
                        onSceneChange: { activeScene = $0 }
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(place.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding(
            get: { Optional(currentID) },
            set: { newValue in
                // Only write real page changes; layout passes (e.g. the keyboard appearing in a
                // sheet) can report the same page again, and every write re-renders the pager.
                if let newValue, newValue != selectedPlaceID {
                    selectedPlaceID = newValue
                    ads.cityPageChanged(hasPlus: purchases.hasPlus)
                }
            }
        ))
        .background { sharedScene }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            PageDots(places: places, currentID: currentID, color: activeSky.textColor)
                .padding(.bottom, 6)
        }
        .overlay {
            // The pager ignores the safe area, so measure the tab bar + home indicator here,
            // where the safe area still applies.
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        }
    }

    /// One scene for the whole pager. A new city's scene fades in over the old one.
    private var sharedScene: some View {
        ZStack {
            EmojiSceneView(
                conditions: activeScene,
                paused: isSceneCovered
            )
            .id(sceneKey)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.6), value: sceneKey)
        .background(activeSky.background(for: activeScene.scene).first ?? .white)
        .ignoresSafeArea()
    }

    /// Changes when the scene or sky changes, which triggers the cross-fade. Cities with the
    /// same weather keep the same scene running, so nothing flickers.
    private var sceneKey: String {
        "\(activeScene.scene.rawValue)-\(activeScene.sky.rawValue)"
    }

    private var topBar: some View {
        HStack {
            #if DEBUG
            debugMenu
            #endif
            Spacer()
            Button {
                showingPlaces = true
            } label: {
                circleIcon("list.bullet")
            }
            .accessibilityLabel("Places")
        }
        .foregroundStyle(activeSky.textColor)
        .padding(.horizontal)
    }

    // MARK: - iPad

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlacesView(selectedPlaceID: $selectedPlaceID, isSidebar: true)
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { debugMenu }
                }
                #endif
        } detail: {
            CityPageView(
                place: currentPlace,
                isActive: true,
                isCovered: showingGallery || !isVisible,
                previewScene: previewScene,
                onSceneChange: { activeScene = $0 }
            )
            .id(currentID)
            // Extend under the status bar and home indicator, but not under the sidebar.
            .ignoresSafeArea(edges: .vertical)
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

    /// Pause the scene while something covers it or another tab is showing.
    private var isSceneCovered: Bool {
        showingPlaces || showingGallery || ads.isShowingFullScreenAd || !isVisible
    }

    private func circleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .background(activeSky.textColor.opacity(0.1), in: Circle())
    }

    #if DEBUG
    private var debugMenu: some View {
        Menu {
            Button {
                showingGallery = true
            } label: {
                Label("Scene Gallery", systemImage: "square.grid.2x2")
            }
            Picker("Show scene on every page", selection: $previewScene) {
                Text("Live weather").tag(WeatherScene?.none)
                ForEach(WeatherScene.allCases) { scene in
                    Text("\(scene.emoji) \(scene.title)").tag(Optional(scene))
                }
            }
            Toggle("EmojiWeather+ unlocked", isOn: Bindable(purchases).debugUnlock)
            Toggle("Show ads", isOn: $debugAdsEnabled)
        } label: {
            circleIcon("ladybug")
        }
        .onChange(of: debugAdsEnabled) { _, enabled in
            if enabled { Task { await ads.start(after: .zero) } }
        }
    }
    #endif
}

/// Page indicator: a location arrow for the current location and a dot per city.
private struct PageDots: View {
    let places: [Place]
    let currentID: String
    var color: Color = .black

    var body: some View {
        HStack(spacing: 8) {
            ForEach(places, id: \.id) { place in
                let isCurrent = place.id == currentID
                Group {
                    if case .currentLocation = place {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9, weight: .bold))
                    } else {
                        Circle().frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(isCurrent ? color : color.opacity(0.25))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.snappy, value: currentID)
        .opacity(places.count > 1 ? 1 : 0)
    }
}
