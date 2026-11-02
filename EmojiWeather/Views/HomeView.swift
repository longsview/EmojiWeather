import CoreLocation
import SwiftUI
import WeatherKit

struct HomeView: View {
    @Environment(LocationService.self) private var location
    @Environment(CityStore.self) private var cityStore
    @Environment(WeatherProvider.self) private var weather
    @Environment(PurchaseManager.self) private var purchases

    /// Per device on purpose: each device remembers which place it was last showing.
    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID

    @State private var snapshot: WeatherSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingPlaces = false
    @State private var previewScene: WeatherScene?

    private var place: Place {
        Place.resolve(id: selectedPlaceID, cities: cityStore.cities)
    }

    private var targetLocation: CLLocation? {
        switch place {
        case .currentLocation: location.location
        case .city(let city): city.location
        }
    }

    private var timeZone: TimeZone {
        switch place {
        case .currentLocation: .current
        case .city(let city): city.timeZone
        }
    }

    private var placeName: String {
        switch place {
        case .currentLocation: location.placeName ?? "My Location"
        case .city(let city): city.name
        }
    }

    private var sceneConditions: SceneConditions {
        if let previewScene { return SceneConditions(scene: previewScene, intensity: 0.8, windDrift: 0.3) }
        if let current = snapshot?.current { return SceneConditions(current: current) }
        return SceneConditions(scene: .cloudy)
    }

    /// Changes whenever the weather should be reloaded.
    private var loadKey: String {
        guard let target = targetLocation else { return "\(place.id)-none" }
        return String(format: "%@-%.2f,%.2f", place.id, target.coordinate.latitude, target.coordinate.longitude)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EmojiSceneView(conditions: sceneConditions)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                            .padding(.top, 140)

                        if case .currentLocation = place, !location.isAuthorized {
                            LocationPermissionCard()
                        }

                        if let snapshot {
                            HourlyForecastView(hours: snapshot.hourly, timeZone: timeZone)
                            DailyForecastView(days: snapshot.daily, timeZone: timeZone)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                        } else if isLoading {
                            ProgressView()
                                .padding()
                        }

                        WeatherAttributionView()
                            .padding(.top, 8)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .refreshable { await load(forceRefresh: true) }
            }
            .environment(\.colorScheme, .dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPlaces = true
                    } label: {
                        Label("Places", systemImage: "list.bullet")
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    debugMenu
                }
                #endif
            }
        }
        .task(id: loadKey) { await load() }
        .sheet(isPresented: $showingPlaces) {
            PlacesView(selectedPlaceID: $selectedPlaceID)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if case .currentLocation = place {
                    Image(systemName: "location.fill").font(.footnote)
                }
                Text(placeName)
            }
            .font(.title2.weight(.semibold))

            if let current = snapshot?.current {
                Text(current.temperature.shortTemperature)
                    .font(.system(size: 96, weight: .thin))
                Text(current.condition.description)
                    .font(.title3)
                if let today = snapshot?.daily.first {
                    Text("H: \(today.highTemperature.shortTemperature)  L: \(today.lowTemperature.shortTemperature)")
                        .font(.headline)
                }
            } else {
                Text("--")
                    .font(.system(size: 96, weight: .thin))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    #if DEBUG
    private var debugMenu: some View {
        Menu {
            Picker("Scene", selection: $previewScene) {
                Text("Live weather").tag(WeatherScene?.none)
                ForEach(WeatherScene.allCases) { scene in
                    Text("\(scene.emoji) \(scene.title)").tag(Optional(scene))
                }
            }
            Toggle("EmojiWeather+ unlocked", isOn: Bindable(purchases).hasPlus)
        } label: {
            Label("Debug", systemImage: "ladybug")
        }
    }
    #endif

    private func load(forceRefresh: Bool = false) async {
        guard let target = targetLocation else {
            snapshot = nil
            return
        }
        // Show cached weather right away when switching places, then refresh if it's stale.
        snapshot = weather.cachedWeather(for: target) ?? (forceRefresh ? snapshot : nil)
        if snapshot != nil, !forceRefresh { return }

        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await weather.weather(for: target, forceRefresh: forceRefresh)
            errorMessage = nil
        } catch is CancellationError {
            // The user switched places; the next load takes over.
        } catch {
            errorMessage = "Couldn't load the weather. Pull down to try again."
        }
    }
}

extension Measurement where UnitType == UnitTemperature {
    /// "72°" in the user's preferred unit.
    var shortTemperature: String {
        formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
