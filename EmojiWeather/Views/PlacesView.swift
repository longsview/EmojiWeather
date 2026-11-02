import SwiftUI

/// The list of places to pick from: the current location plus saved cities synced through iCloud.
struct PlacesView: View {
    @Binding var selectedPlaceID: String

    @Environment(CityStore.self) private var cityStore
    @Environment(LocationService.self) private var location
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddCity = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    placeRow(
                        id: Place.currentLocationID,
                        emoji: "📍",
                        title: location.placeName ?? "My Location",
                        subtitle: location.isAuthorized ? "Current location" : "Location access is off"
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCity) {
                AddCityView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(reason: "Free includes \(PurchaseManager.freeCityLimit) cities. EmojiWeather+ removes the limit.")
            }
        }
    }

    private var footerText: String {
        var text = "Your cities sync to all your devices through iCloud."
        if !purchases.hasPlus {
            text += " Free includes \(PurchaseManager.freeCityLimit) cities (\(cityStore.cities.count) used)."
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
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(emoji).font(.title2)
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
    }
}
