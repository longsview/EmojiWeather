#if DEBUG
import SwiftUI

/// Debug-only gallery: swipe through every weather scene with sample text on top, and tweak rain
/// intensity and wind to see how each scene reacts, without hunting for a city with that weather.
struct SceneGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selection: WeatherScene = .sunny
    @State private var intensity = 0.8
    @State private var wind = 0.3
    /// Applied when a slider is released, because each change restarts the scene.
    @State private var appliedIntensity = 0.8
    @State private var appliedWind = 0.3
    @State private var showsText = true
    @State private var showsControls = true
    @State private var restartCount = 0
    @State private var sky: SkyMode = .day

    var body: some View {
        TabView(selection: $selection) {
            ForEach(WeatherScene.allCases) { scene in
                page(for: scene)
                    .tag(scene)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.skyMode, sky)
        .background(sky.background.first ?? .white)
        .ignoresSafeArea()
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottom) {
            if showsControls { controls }
        }
        .preferredColorScheme(sky.isDark ? .dark : .light)
    }

    private func page(for scene: WeatherScene) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                EmojiSceneView(
                    conditions: SceneConditions(scene: scene, intensity: appliedIntensity, windDrift: appliedWind, sky: sky),
                    paused: scene != selection
                )
                .id("\(scene.rawValue)-\(restartCount)")
                if showsText {
                    VStack(spacing: 0) {
                        Spacer().frame(height: proxy.size.height * 0.47)
                        WeatherSummaryView(
                            placeName: "Preview City",
                            temperature: scene.sampleTemperature,
                            condition: scene.title,
                            high: scene.sampleHigh,
                            low: scene.sampleLow,
                            tagline: scene.tagline
                        )
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(sky.textColor.opacity(0.1), in: Circle())
            }
            Spacer()
            Text("\(selection.emoji) \(selection.title)  \(index + 1)/\(WeatherScene.allCases.count)")
                .font(.system(.headline, design: .rounded))
            Spacer()
            Button {
                withAnimation(.snappy) { showsControls.toggle() }
            } label: {
                Image(systemName: showsControls ? "slider.horizontal.below.rectangle" : "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(sky.textColor.opacity(0.1), in: Circle())
            }
        }
        .foregroundStyle(sky.textColor)
        .padding(.horizontal)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shown for: \(selection.weatherKitConditions)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Sky", selection: $sky) {
                ForEach(SkyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            sliderRow("Intensity", value: $intensity, range: 0.2...1) { appliedIntensity = intensity }
            sliderRow("Wind", value: $wind, range: -1...1) { appliedWind = wind }

            HStack {
                Toggle("Text", isOn: $showsText)
                    .fixedSize()
                Spacer()
                Button("Restart scene") {
                    restartCount += 1
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           commit: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 72, alignment: .leading)
            Slider(value: value, in: range) { editing in
                if !editing { commit() }
            }
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(1))))
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var index: Int {
        WeatherScene.allCases.firstIndex(of: selection) ?? 0
    }
}

private extension WeatherScene {
    var sampleTemperature: String {
        switch self {
        case .thunderstorm: "71°"
        case .rain: "58°"
        case .snow: "28°"
        case .sunny: "75°"
        case .clearNight: "62°"
        case .cloudy: "64°"
        case .windy: "60°"
        case .foggy: "55°"
        case .hot: "103°"
        }
    }

    var sampleHigh: String {
        switch self {
        case .hot: "106°"
        case .snow: "31°"
        default: "78°"
        }
    }

    var sampleLow: String {
        switch self {
        case .hot: "84°"
        case .snow: "19°"
        default: "52°"
        }
    }

    /// Which WeatherKit conditions map to this scene (see `WeatherScene.init(condition:isDaylight:)`).
    var weatherKitConditions: String {
        switch self {
        case .thunderstorm: "thunderstorms (isolated, scattered, strong), tropical storm, hurricane"
        case .rain: "drizzle, rain, heavy rain, sun showers, freezing rain, hail, sleet, wintry mix"
        case .snow: "snow, heavy snow, flurries, blizzard, blowing snow, frigid"
        case .sunny: "clear, mostly clear, partly cloudy (daytime)"
        case .clearNight: "clear, mostly clear, partly cloudy, hot (night)"
        case .cloudy: "cloudy, mostly cloudy"
        case .windy: "windy, breezy"
        case .foggy: "fog, haze, smoke, blowing dust"
        case .hot: "hot (daytime)"
        }
    }
}

#Preview {
    SceneGalleryView()
}
#endif
