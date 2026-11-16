import MapKit
import SwiftUI

/// The 80s TV weather map: big emoji and chunky temperatures over a map. Panning and zooming
/// fetch more of them as needed.
struct WeatherMapView: View {
    /// Where the map starts.
    let center: CLLocationCoordinate2D?

    @State private var model = MapWeatherModel()
    @State private var radar = RadarModel()
    @AppStorage("map.radar") private var showsRadar = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition
    /// The visible region, updated while panning so the radar image and emoji move with the map.
    @State private var liveRegion: MKCoordinateRegion?

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
        // The radar has to sit between the map and the emoji, and SwiftUI's Map can't layer
        // images itself, so both are drawn on top of it and positioned with the map's proxy.
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapScaleView()
            }
            .overlay {
                ZStack(alignment: .topLeading) {
                    // Reading the live region redraws this on every camera move, so it tracks the map.
                    let _ = liveRegion
                    if showsRadar, let radarImage = radar.image, let frame = radarFrame(radarImage.region, proxy: proxy) {
                        Image(uiImage: radarImage.image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .opacity(0.7)
                            .accessibilityHidden(true)
                    }
                    ForEach(model.markers) { marker in
                        if let point = proxy.convert(marker.coordinate, to: .local) {
                            EmojiMapMarker(name: marker.name, emoji: marker.emoji, temperature: marker.temperature.shortTemperature)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(verbatim: "\(marker.name), \(marker.condition), \(marker.temperature.spokenTemperature)"))
                                .fixedSize()
                                .position(point)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .spring(duration: 0.4), value: model.markers.map(\.id))
            }
            .onMapCameraChange(frequency: .continuous) { context in
                liveRegion = context.region
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                lastRegion = context.region
                model.update(region: context.region)
                radar.update(region: context.region, fetches: showsRadar)
            }
        }
        // Insets (not overlays) so the header and attribution clear the status bar and the tab
        // bar, and the map keeps its markers out from under them.
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) {
            // Apple requires the Weather mark wherever WeatherKit data is shown; the rest of the
            // credits are in Settings > Data Sources.
            VStack(spacing: 4) {
                WeatherAttributionView()
                if showsRadar, radar.coversVisibleArea {
                    Text("Radar: NOAA/National Weather Service")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.bottom, 8)
        }
        .onChange(of: showsRadar) { _, on in
            if on, let lastRegion { radar.update(region: lastRegion) }
        }
        .task {
            // Radar scans update every few minutes; refresh while the map is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                if showsRadar, let lastRegion { radar.update(region: lastRegion, force: true) }
            }
        }
    }

    @State private var lastRegion: MKCoordinateRegion?

    /// Where the radar image's region currently sits on screen.
    private func radarFrame(_ region: RadarModel.Bounds, proxy: MapProxy) -> CGRect? {
        guard let topLeft = proxy.convert(CLLocationCoordinate2D(latitude: region.north, longitude: region.west), to: .local),
              let bottomRight = proxy.convert(CLLocationCoordinate2D(latitude: region.south, longitude: region.east), to: .local)
        else { return nil }
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    private var header: some View {
        HStack {
            Text("Weather Map")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            if model.isLoading || radar.isLoading {
                ProgressView().controlSize(.small)
            }
            if radar.coversVisibleArea {
                Button {
                    showsRadar.toggle()
                } label: {
                    Label("Radar", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(showsRadar ? Color.green.opacity(0.25) : Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(showsRadar ? "On" : "Off"))
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

/// Precipitation radar from the National Weather Service: a mosaic of its Doppler radars, updated
/// every few minutes. Public domain and free, no key. It covers the US (with Alaska, Hawaii and
/// Puerto Rico) and southern Canada; elsewhere the layer is simply hidden.
@MainActor
@Observable
final class RadarModel {
    struct Bounds: Equatable {
        let north: Double, south: Double, west: Double, east: Double
    }

    struct RadarImage {
        let image: UIImage
        let region: Bounds
    }

    private(set) var image: RadarImage?
    private(set) var isLoading = false
    /// Whether the visible area overlaps the radar's coverage, so the button and credit show.
    private(set) var coversVisibleArea = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastBounds: Bounds?
    @ObservationIgnored private var fetchedAt: Date = .distantPast

    private static let endpoint = "https://mapservices.weather.noaa.gov/eventdriven/rest/services/radar/radar_base_reflectivity/MapServer/export"

    /// The radar network's rough extent: the lower 48, Alaska, Hawaii, Puerto Rico, southern Canada.
    private static let coverage: [Bounds] = [
        Bounds(north: 60, south: 23, west: -128, east: -64),
        Bounds(north: 72, south: 51, west: -170, east: -129),
        Bounds(north: 23, south: 18, west: -161, east: -154),
        Bounds(north: 19.5, south: 17, west: -68.5, east: -64.5),
    ]

    /// Call when the map stops moving. `fetches` is false while the layer is switched off, so
    /// only the coverage check (for the button) runs.
    func update(region: MKCoordinateRegion, fetches: Bool = true, force: Bool = false) {
        let bounds = Bounds(
            north: min(region.center.latitude + region.span.latitudeDelta / 2, 85),
            south: max(region.center.latitude - region.span.latitudeDelta / 2, -85),
            west: region.center.longitude - region.span.longitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2
        )
        coversVisibleArea = Self.coverage.contains { area in
            bounds.south < area.north && bounds.north > area.south && bounds.west < area.east && bounds.east > area.west
        }
        guard coversVisibleArea else {
            image = nil
            return
        }
        guard fetches else { return }
        let isFresh = Date.now.timeIntervalSince(fetchedAt) < 4 * 60
        if !force, isFresh, bounds == lastBounds { return }

        task?.cancel()
        task = Task {
            // Wait a moment so a fling or pinch doesn't fetch every stop along the way.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isLoading = true
            defer { isLoading = false }
            guard let fetched = await Self.fetch(bounds), !Task.isCancelled else { return }
            image = fetched
            lastBounds = bounds
            fetchedAt = .now
        }
    }

    /// Asks the map service for one transparent PNG covering the bounds, in Web Mercator
    /// (the same projection as Apple Maps), so it lines up when stretched over the region.
    private static func fetch(_ bounds: Bounds) async -> RadarImage? {
        func mercator(_ latitude: Double, _ longitude: Double) -> (x: Double, y: Double) {
            let radius = 6_378_137.0
            let x = longitude * .pi / 180 * radius
            let y = log(tan(.pi / 4 + latitude * .pi / 360)) * radius
            return (x, y)
        }
        let southWest = mercator(bounds.south, bounds.west)
        let northEast = mercator(bounds.north, bounds.east)
        // About one image pixel per screen point, wide side 1,024 (the radar is 1 km anyway).
        let aspect = (northEast.y - southWest.y) / max(northEast.x - southWest.x, 1)
        let width = 1_024
        let height = max(64, min(2_048, Int(Double(width) * aspect)))
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "bbox", value: "\(southWest.x),\(southWest.y),\(northEast.x),\(northEast.y)"),
            URLQueryItem(name: "bboxSR", value: "3857"),
            URLQueryItem(name: "imageSR", value: "3857"),
            URLQueryItem(name: "size", value: "\(width),\(height)"),
            URLQueryItem(name: "format", value: "png32"),
            URLQueryItem(name: "transparent", value: "true"),
            URLQueryItem(name: "f", value: "image"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Skymoji/1.0 (getskymoji@gmail.com)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        return RadarImage(image: image, region: bounds)
    }
}
