import MapKit
import SwiftUI

/// The 80s TV weather map: big emoji and chunky temperatures over a map. Panning and zooming
/// fetch more of them as needed.
struct WeatherMapView: View {
    /// Where the map starts.
    let center: CLLocationCoordinate2D?

    @State private var model = MapWeatherModel()
    @State private var position: MapCameraPosition

    init(center: CLLocationCoordinate2D?) {
        self.center = center
        if let center {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
            )))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        Map(position: $position) {
            ForEach(model.markers) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    EmojiMapMarker(emoji: marker.emoji, temperature: marker.temperature.shortTemperature)
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
        .animation(.spring(duration: 0.4), value: model.markers.map(\.id))
        .onMapCameraChange(frequency: .onEnd) { context in
            model.update(region: context.region)
        }
        // Insets (not overlays) so the header and attribution clear the status bar and the tab
        // bar, and the map keeps its markers out from under them.
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) {
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
        }
        .accessibilityElement(children: .combine)
    }
}
