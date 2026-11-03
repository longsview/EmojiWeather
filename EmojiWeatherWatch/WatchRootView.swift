import SwiftUI
import WatchKit

/// Swipe sideways between My Location and the saved cities, like the iPhone app.
/// Each page scrolls down (or turn the Digital Crown) for the hourly, conditions and 10-day forecast.
struct WatchRootView: View {
    @Environment(LocationService.self) private var location
    @Environment(CityStore.self) private var cityStore

    @AppStorage("watch.selectedPlace") private var selectedID = Place.currentLocationID

    private var places: [Place] {
        let cities = cityStore.cities.map(Place.city)
        // With location turned off, skip the My Location page if there are cities to show.
        if location.isDenied, !cities.isEmpty { return cities }
        return [.currentLocation] + cities
    }

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(places, id: \.id) { place in
                WatchCityPage(place: place, isActive: place.id == selectedID)
                    .tag(place.id)
            }
        }
        .tabViewStyle(.page)
        .onChange(of: selectedID) { _, _ in
            WKInterfaceDevice.current().play(.click)
        }
        .onChange(of: places.map(\.id), initial: true) { _, ids in
            // The selected city was deleted (maybe on the phone): go back to the first page.
            if !ids.contains(selectedID), let first = ids.first {
                selectedID = first
            }
        }
    }
}
