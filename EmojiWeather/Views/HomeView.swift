import SwiftUI

/// iPhone: full-screen pages, one per place; swipe left and right between them.
/// iPad (regular width): a split view with the places list on the left and the city on the right.
struct HomeView: View {
    /// False while the Map tab is showing, so the scene can pause.
    var isVisible = true

    @Environment(CityStore.self) private var cityStore
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AdsManager.self) private var ads
    @Environment(QuizStore.self) private var quiz
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Per device on purpose: each device remembers which place it was last showing.
    @AppStorage("selectedPlaceID") private var selectedPlaceID = Place.currentLocationID

    @State private var showingPlaces = false
    @State private var showingQuiz = false
    /// The "today's quiz is ready" bottom sheet, offered at most once a day.
    @State private var showingQuizNudge = false
    @State private var playAfterNudge = false
    @AppStorage("quiz.lastNudgeDay") private var lastNudgeDay = ""
    @Environment(\.scenePhase) private var scenePhase
    /// Height covered by the tab bar and home indicator, so the bottom controls sit above it.
    @State private var bottomInset: CGFloat = 0
    /// Bumped by the fixed Forecast hint to open the visible page's forecast.
    @State private var openDetailsToken = 0
    /// Bumped by the Share button to share the visible page.
    @State private var shareToken = 0
    @State private var activeHasWeather = false
    @State private var previewScene: WeatherScene? = {
        #if DEBUG
        return ScreenshotMode.scene
        #else
        return nil
        #endif
    }()
    @State private var showingGallery = false
    /// The visible page's scene. On iPhone it's drawn once behind all pages, so swiping
    /// slides only the text while the scene cross-fades.
    @State private var activeScene = SceneConditions(scene: .cloudy)
    private var activeSky: SkyMode { activeScene.sky }
    /// iPad: keep the places list and the city side by side.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if DEBUG
    @AppStorage(AdsManager.debugAdsEnabledKey) private var debugAdsEnabled = false
    #endif

    private var places: [Place] {
        [.currentLocation] + cityStore.cities.map { Place.city($0) }
    }

    /// The selected place, falling back to the current location if that city was deleted.
    private var currentPlace: Place {
        Place.resolve(id: selectedPlaceID, cities: cityStore.cities)
    }

    private var currentID: String { currentPlace.id }

    private var currentIndex: Int { places.firstIndex { $0.id == currentID } ?? 0 }

    private var currentPlaceName: String {
        switch currentPlace {
        case .currentLocation: String(localized: "My Location")
        case .city(let city): city.name
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                pager
            }
        }
        .preferredColorScheme(activeSky.isDark ? .dark : .light)
        .sheet(isPresented: $showingQuiz) {
            QuizView()
        }
        .sheet(isPresented: $showingQuizNudge, onDismiss: {
            if playAfterNudge {
                playAfterNudge = false
                showingQuiz = true
            }
        }) {
            QuizNudgeSheet(streak: quiz.currentStreak) {
                AppAnalytics.log(.quizNudgeAccepted)
                playAfterNudge = true
                showingQuizNudge = false
            } onDismiss: {
                showingQuizNudge = false
            }
        }
        // Offer today's quiz once the weather is up, and again on the next day's first open.
        .task(id: activeHasWeather) { await nudgeIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await nudgeIfNeeded() } }
        }
        // The streak widget opens the quiz with skymoji://daily.
        .onOpenURL { url in
            if url.scheme == "skymoji", url.host == "daily" { showingQuiz = true }
        }
        #if DEBUG
        .task { await runScreenshotMode() }
        #endif
        // A tapped morning reminder.
        .onChange(of: quiz.openRequested, initial: true) {
            guard quiz.openRequested else { return }
            quiz.openRequested = false
            showingQuiz = true
        }
        .sheet(isPresented: $showingPlaces) {
            PlacesView(selectedPlaceID: $selectedPlaceID)
        }

        #if DEBUG
        .fullScreenCover(isPresented: $showingGallery) {
            SceneGalleryView()
        }
        #endif
    }

    // MARK: - iPhone

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(places, id: \.id) { place in
                    CityPageView(
                        place: place,
                        isActive: place.id == currentID,
                        isCovered: isSceneCovered,
                        previewScene: previewScene,
                        showsScene: false,
                        bottomInset: bottomInset,
                        onSceneChange: { activeScene = $0 },
                        openDetailsToken: openDetailsToken,
                        shareToken: shareToken,
                        onHasWeatherChange: { activeHasWeather = $0 }
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(place.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding(
            get: { Optional(currentID) },
            set: { newValue in
                // Only write real page changes; layout passes (e.g. the keyboard appearing in a
                // sheet) can report the same page again, and every write re-renders the pager.
                if let newValue, newValue != selectedPlaceID {
                    selectedPlaceID = newValue
                    ads.cityPageChanged(hasPlus: purchases.hasPlus)
                }
            }
        ))
        .background { sharedScene }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            // Fixed while the cities swipe; only each page's text moves.
            VStack(spacing: 8) {
                ForecastHint(color: activeSky.textColor, isEnabled: activeHasWeather) {
                    openDetailsToken += 1
                }
                PageDots(places: places, currentID: currentID, color: activeSky.textColor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Page \(currentIndex + 1) of \(places.count)"))
                    .accessibilityValue(Text(currentPlaceName))
                    // Swipe up or down with VoiceOver to change city, like a page control.
                    .accessibilityAdjustableAction { direction in
                        let next: Int
                        switch direction {
                        case .increment: next = min(currentIndex + 1, places.count - 1)
                        case .decrement: next = max(currentIndex - 1, 0)
                        @unknown default: next = currentIndex
                        }
                        selectedPlaceID = places[next].id
                    }
            }
            .padding(.bottom, 6)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .overlay {
            // The pager ignores the safe area, so measure the tab bar + home indicator here,
            // where the safe area still applies.
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        }
    }

    /// One scene for the whole pager. A new city's scene fades in over the old one.
    private var sharedScene: some View {
        ZStack {
            EmojiSceneView(
                conditions: activeScene,
                paused: isSceneCovered
            )
            .id(sceneKey)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.6), value: sceneKey)
        .background(activeSky.background(for: activeScene.scene).first ?? .white)
        .ignoresSafeArea()
    }

    /// Changes when the scene or sky changes, which triggers the cross-fade. Cities with the
    /// same weather keep the same scene running, so nothing flickers.
    private var sceneKey: String {
        "\(activeScene.scene.rawValue)-\(activeScene.sky.rawValue)"
    }

    private var topBar: some View {
        HStack {
            #if DEBUG
            if !ScreenshotMode.isActive { debugMenu }
            #endif
            quizButton
            Spacer()
            if activeHasWeather {
                Button {
                    shareToken += 1
                } label: {
                    circleIcon("square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            Button {
                showingPlaces = true
            } label: {
                circleIcon("list.bullet")
            }
            .accessibilityLabel("Places")
        }
        .foregroundStyle(activeSky.textColor)
        .padding(.horizontal)
    }

    // MARK: - iPad

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlacesView(selectedPlaceID: $selectedPlaceID, isSidebar: true)
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if !ScreenshotMode.isActive { debugMenu }
                    }
                }
                #endif
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { quizButton }
                }
        } detail: {
            CityPageView(
                place: currentPlace,
                isActive: true,
                isCovered: showingGallery || !isVisible,
                previewScene: previewScene,
                onSceneChange: { activeScene = $0 },
                openDetailsToken: openDetailsToken,
                shareToken: shareToken,
                onHasWeatherChange: { activeHasWeather = $0 }
            )
            .id(currentID)
            // Extend under the status bar and home indicator, but not under the sidebar.
            .ignoresSafeArea(edges: .vertical)
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

    /// Shows the daily quiz nudge if today's quiz isn't done and it hasn't been offered today.
    private func nudgeIfNeeded() async {
        #if DEBUG
        if ScreenshotMode.isActive { return }
        #endif
        guard activeHasWeather, isVisible, lastNudgeDay != QuizStore.today else { return }
        // Let the weather land first, and wait for any consent or tracking prompt to finish.
        try? await Task.sleep(for: .seconds(4))
        for _ in 0..<60 where ads.isPrompting {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard !Task.isCancelled, !ads.isPrompting, !ads.isShowingFullScreenAd,
              !quiz.hasPlayedToday, !showingQuiz, !showingPlaces, !showingGallery,
              lastNudgeDay != QuizStore.today else { return }
        lastNudgeDay = QuizStore.today
        AppAnalytics.log(.quizNudgeShown)
        showingQuizNudge = true
    }

    /// Opens Skymoji Daily. Shows the streak, and a check once today's quiz is done.
    private var quizButton: some View {
        Button {
            showingQuiz = true
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: quiz.hasPlayedToday ? "✅" : "🧩")
                if quiz.currentStreak > 0 {
                    Text(verbatim: "🔥\(quiz.currentStreak)")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(activeSky.textColor.opacity(0.1), in: Capsule())
        }
        .accessibilityLabel(Text("Skymoji Daily quiz"))
        .accessibilityValue(quiz.currentStreak > 0 ? Text("\(quiz.currentStreak)-day streak") : Text(verbatim: ""))
    }

    /// Pause the scene while something covers it or another tab is showing.
    private var isSceneCovered: Bool {
        showingPlaces || showingGallery || ads.isShowingFullScreenAd || !isVisible
    }

    private func circleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .background(activeSky.textColor.opacity(0.1), in: Circle())
    }

    #if DEBUG
    private var debugMenu: some View {
        Menu {
            Toggle("Show ads", isOn: $debugAdsEnabled)
            Toggle("Skymoji+ unlocked", isOn: Bindable(purchases).debugUnlock)
            Button {
                showingGallery = true
            } label: {
                Label("Scene Gallery", systemImage: "square.grid.2x2")
            }
            Picker(selection: $previewScene) {
                Text("Live weather").tag(WeatherScene?.none)
                ForEach(WeatherScene.allCases) { scene in
                    Text(verbatim: "\(scene.emoji) \(scene.title)").tag(Optional(scene))
                }
            } label: {
                Label("Show scene on every page", systemImage: "photo.on.rectangle")
            }
            .pickerStyle(.menu)
        } label: {
            circleIcon("ladybug")
        }
        .onChange(of: debugAdsEnabled) { _, enabled in
            if enabled { Task { await ads.start(after: .zero) } }
        }
    }
    #endif
}

/// Page indicator: a location arrow for the current location and a dot per city.
private struct PageDots: View {
    let places: [Place]
    let currentID: String
    var color: Color = .black

    var body: some View {
        HStack(spacing: 8) {
            ForEach(places, id: \.id) { place in
                let isCurrent = place.id == currentID
                Group {
                    if case .currentLocation = place {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9, weight: .bold))
                    } else {
                        Circle().frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(isCurrent ? color : color.opacity(0.25))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.snappy, value: currentID)
        .opacity(places.count > 1 ? 1 : 0)
    }
}

#if DEBUG
extension HomeView {
    /// Opens the screen named by `-SkymojiOpen` once the weather has loaded (see ScreenshotMode).
    func runScreenshotMode() async {
        if let name = ScreenshotMode.city,
           let city = cityStore.cities.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            selectedPlaceID = city.id.uuidString
        }
        guard let open = ScreenshotMode.open else { return }
        // Wait for the weather (and so the location) before opening anything, up to 30 s.
        for _ in 0..<60 where !activeHasWeather {
            try? await Task.sleep(for: .milliseconds(500))
        }
        try? await Task.sleep(for: .seconds(1.5))
        switch open {
        case "forecast": openDetailsToken += 1
        case "share": shareToken += 1
        case "quiz":
            showingQuiz = true
        case "quizSummary":
            showingQuiz = true
            try? await Task.sleep(for: .seconds(4))
            quiz.debugAnswerAll()
        default: break
        }
    }
}
#endif
