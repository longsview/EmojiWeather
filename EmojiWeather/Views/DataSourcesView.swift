import SwiftUI

/// Credits for the data the app shows, reached from Settings > Data Sources.
struct DataSourcesView: View {
    var body: some View {
        List {
            Section {
                WeatherAttributionView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Forecasts, current conditions and the weather map come from Apple's WeatherKit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Weather")
            }

            Section {
                Link(destination: URL(string: "https://www.geonames.org")!) {
                    Label("GeoNames", systemImage: "globe")
                }
                Link(destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!) {
                    Label("Creative Commons Attribution 4.0", systemImage: "doc.text")
                }
                Text("The towns and cities on the weather map come from GeoNames, used under CC BY 4.0. Only names, locations and populations are used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cities")
            }

            Section {
                Text("Maps and place search are provided by Apple Maps. Map data credits are on the map itself.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Maps")
            }

            Section {
                Link(destination: URL(string: "https://policies.google.com/technologies/partner-sites")!) {
                    Label("How Google uses data from apps", systemImage: "hand.raised")
                }
                Text("The free version shows ads from Google AdMob. EmojiWeather+ removes them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Advertising")
            }
        }
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
