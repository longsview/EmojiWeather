import MapKit
import SwiftUI

struct AddCityView: View {
    @Environment(CityStore.self) private var cityStore
    @Environment(\.dismiss) private var dismiss

    @State private var search = CitySearchModel()
    @State private var query = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(search.results, id: \.self) { completion in
                Button {
                    Task { await add(completion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completion.title).foregroundStyle(.primary)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isResolving)
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "Search for a city",
                        systemImage: "magnifyingglass",
                        description: Text("Try Tokyo, Austin or Paris.")
                    )
                } else if search.results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .overlay {
                if isResolving { ProgressView() }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City name")
            .onChange(of: query) { _, newValue in
                search.update(query: newValue)
            }
            .navigationTitle("Add City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Couldn't add that city",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let city = try await search.resolve(completion)
            if cityStore.add(city) {
                dismiss()
            } else {
                errorMessage = "\(city.name) is already in your list."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
