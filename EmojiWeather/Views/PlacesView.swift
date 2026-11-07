import SwiftUI

/// The list of places to pick from: the current location plus saved cities synced through iCloud.
/// Shown as a sheet on iPhone and as the sidebar of the split layout on iPad.
struct PlacesView: View {
    @Binding var selectedPlaceID: String
    /// In the iPad sidebar: no Done button, and picking a place doesn't dismiss anything.
    var isSidebar = false

    @Environment(CityStore.self) private var cityStore
    @Environment(LocationService.self) private var location
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddCity = false
    @State private var showingPaywall = false

    var body: some View {
        if isSidebar {
            list
        } else {
            NavigationStack {
                list
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }

    private var list: some View {
            List {
                Section {
                    placeRow(
                        id: Place.currentLocationID,
                        emoji: "📍",
                        title: location.placeName ?? String(localized: "My Location"),
                        subtitle: location.isAuthorized ? String(localized: "Current location") : String(localized: "Location access is off")
                    )
                }

                Section {
                    ForEach(cityStore.cities) { city in
                        placeRow(id: city.id.uuidString, emoji: "🏙️", title: city.name, subtitle: city.region)
                    }
                    .onDelete { cityStore.remove(atOffsets: $0) }
                    .onMove { cityStore.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        addCityTapped()
                    } label: {
                        Label("Add City", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Cities")
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddCity) {
                AddCityView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(reason: String(localized: "Free includes \(PurchaseManager.freeCityLimit) cities. Skymoji+ removes the limit."))
            }
    }

    private var footerText: String {
        var text = String(localized: "Your cities sync to all your devices through iCloud.")
        if !purchases.hasPlus {
            text += " " + String(localized: "Free includes \(PurchaseManager.freeCityLimit) cities (\(cityStore.cities.count) used).")
        }
        return text
    }

    private func addCityTapped() {
        if purchases.canAddCity(currentCount: cityStore.cities.count) {
            showingAddCity = true
        } else {
            showingPaywall = true
        }
    }

    private func placeRow(id: String, emoji: String, title: String, subtitle: String) -> some View {
        Button {
            selectedPlaceID = id
            if !isSidebar { dismiss() }
        } label: {
            HStack(spacing: 12) {
                Text(emoji).font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedPlaceID == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .listRowBackground(isSidebar && selectedPlaceID == id ? Color.accentColor.opacity(0.15) : nil)
        .accessibilityAddTraits(selectedPlaceID == id ? .isSelected : [])
    }
}
