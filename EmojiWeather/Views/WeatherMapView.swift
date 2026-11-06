import MapKit
import SwiftUI

/// The 80s TV weather map: big emoji and chunky temperatures over a map. Panning and zooming
/// fetch more of them as needed.
struct WeatherMapView: View {
    /// Where the map starts.
    let center: CLLocationCoordinate2D?

    @State private var model = MapWeatherModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition

    init(center: CLLocationCoordinate2D?) {
        self.center = center
        // Always a fixed region: `.automatic` fits the camera to the markers, which loads markers
        // for the new region, which refits... and the map zooms in until one marker is left.
        var region = Self.defaultRegion
        if let center {
            region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
        }
        #if DEBUG
        if ScreenshotMode.isActive { region = Self.screenshotRegion }
        #endif
        _position = State(initialValue: .region(region))
    }

    /// Without a location or a saved city: the reader's country when we know roughly where it
    /// is, otherwise the continental US.
    private static var defaultRegion: MKCoordinateRegion {
        let regions: [String: (Double, Double, Double)] = [
            "US": (39.5, -98.5, 28), "CA": (50, -96, 35), "GB": (54, -2.5, 10), "FR": (46.6, 2.4, 10),
            "ES": (40.2, -3.7, 10), "MX": (23.6, -102.5, 18), "BR": (-14.2, -51.9, 30), "PT": (39.6, -8, 6),
            "DE": (51.2, 10.4, 9), "IT": (42.5, 12.6, 10), "JP": (36.5, 138, 14), "CN": (35, 104, 32),
            "AU": (-25.3, 133.8, 35), "IN": (21, 78, 28), "SA": (24, 45, 20), "AE": (24.4, 54.4, 6),
            "EG": (26.8, 30.8, 14),
        ]
        let code = Locale.current.region?.identifier ?? "US"
        let (lat, lon, span) = regions[code] ?? regions["US"]!
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                  span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }

    #if DEBUG
    /// Screenshots show a country that fits each language: the US in English, France in French,
    /// Spain, Brazil, China, Japan and Saudi Arabia, wide enough for a map full of big cities.
    private static var screenshotRegion: MKCoordinateRegion {
        let byLanguage: [String: (Double, Double, Double)] = [
            "en": (39.5, -98.5, 28), "fr": (46.6, 2.4, 10), "es": (40.2, -3.7, 10), "pt": (-14.2, -51.9, 30),
            "zh": (33, 110, 26), "ja": (36.5, 138, 14), "ar": (24, 45, 20),
        ]
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let (lat, lon, span) = byLanguage[code] ?? byLanguage["en"]!
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                  span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }
    #endif

    var body: some View {
        Map(position: $position) {
            ForEach(model.markers) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    EmojiMapMarker(name: marker.name, emoji: marker.emoji, temperature: marker.temperature.shortTemperature)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(marker.name), \(marker.condition), \(marker.temperature.spokenTemperature)"))
                        .transition(.scale.combined(with: .opacity))
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapScaleView()
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: model.markers.map(\.id))
        .onMapCameraChange(frequency: .onEnd) { context in
            model.update(region: context.region)
        }
        // Insets (not overlays) so the header and attribution clear the status bar and the tab
        // bar, and the map keeps its markers out from under them.
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) {
            // Apple requires the Weather mark wherever WeatherKit data is shown; the rest of the
            // credits are in Settings > Data Sources.
            WeatherAttributionView()
                .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        HStack {
            Text("Weather Map")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
    }
}

/// A big emoji over a chunky white temperature with a dark outline, like the old TV maps.
private struct EmojiMapMarker: View {
    let name: String
    let emoji: String
    let temperature: String

    var body: some View {
        VStack(spacing: -6) {
            Text(emoji)
                .font(.system(size: 48))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Text(temperature)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                // Four hard shadows make a cheap outline.
                .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: .black, radius: 0, x: -1.5, y: -1.5)
                .shadow(color: .black, radius: 0, x: 1.5, y: -1.5)
                .shadow(color: .black, radius: 0, x: -1.5, y: 1.5)
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }
}
