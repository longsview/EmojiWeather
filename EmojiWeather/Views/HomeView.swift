import SwiftUI

/// iPhone: full-screen pages, one per place; swipe left and right between them.
/// iPad (regular width): a split view with the places list on the left and the city on the right.
struct HomeView: View {
    @Environment(CityStore.self) private var cityStore
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AdsManager.self) private var ads
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Per device on purpose: each device remembers which place it was last showing.
    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID

    @State private var showingPlaces = false
    @State private var previewScene: WeatherScene?
    @State private var showingGallery = false
    /// The sky of the visible page, so the buttons and status bar can match it.
    @State private var activeSky: SkyMode = .day
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
                        isCovered: showingPlaces || showingGallery || ads.isShowingFullScreenAd,
                        previewScene: previewScene,
                        onSkyChange: { activeSky = $0 }
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
        .background(activeSky.background.first ?? .white)
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            PageDots(places: places, currentID: currentID, color: activeSky.textColor)
                .padding(.bottom, 6)
        }
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
                isCovered: showingGallery,
                previewScene: previewScene,
                onSkyChange: { activeSky = $0 }
            )
            .id(currentID)
            // Extend under the status bar and home indicator, but not under the sidebar.
            .ignoresSafeArea(edges: .vertical)
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

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
