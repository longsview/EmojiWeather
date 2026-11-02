import SwiftUI

/// Full-screen pages, one per place. Swipe left and right to move between the current location
/// and saved cities.
struct HomeView: View {
    @Environment(CityStore.self) private var cityStore
    @Environment(PurchaseManager.self) private var purchases

    /// Per device on purpose: each device remembers which place it was last showing.
    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID

    @State private var showingPlaces = false
    @State private var previewScene: WeatherScene?
    @State private var showingGallery = false

    private var places: [Place] {
        [.currentLocation] + cityStore.cities.map { Place.city($0) }
    }

    /// The selected page, falling back to the current location if that city was deleted.
    private var currentID: String {
        Place.resolve(id: selectedPlaceID, cities: cityStore.cities).id
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(places, id: \.id) { place in
                    CityPageView(
                        place: place,
                        isActive: place.id == currentID,
                        isCovered: showingPlaces || showingGallery,
                        previewScene: previewScene
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
                if let newValue, newValue != selectedPlaceID { selectedPlaceID = newValue }
            }
        ))
        .background(Color.white)
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            PageDots(places: places, currentID: currentID)
                .padding(.bottom, 6)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingPlaces) {
            PlacesView(selectedPlaceID: $selectedPlaceID)
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showingGallery) {
            SceneGalleryView()
        }
        #endif
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
                Image(systemName: "list.bullet")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("Places")
        }
        .foregroundStyle(.black)
        .padding(.horizontal)
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
            Toggle("EmojiWeather+ unlocked", isOn: Bindable(purchases).hasPlus)
        } label: {
            Image(systemName: "ladybug")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.06), in: Circle())
        }
    }
    #endif
}

/// Page indicator: a location arrow for the current location and a dot per city.
private struct PageDots: View {
    let places: [Place]
    let currentID: String

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
                .foregroundStyle(isCurrent ? Color.black : Color.black.opacity(0.2))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.snappy, value: currentID)
        .opacity(places.count > 1 ? 1 : 0)
    }
}

extension Measurement where UnitType == UnitTemperature {
    /// "72°" in the user's preferred unit.
    var shortTemperature: String {
        formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
