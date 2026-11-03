import Foundation
import GoogleMobileAds
import Observation
import os
import UIKit
import UserMessagingPlatform

/// Google AdMob for the free tier: a small banner on the current-location page, a card in the
/// forecast sheet, and an occasional full-screen ad when swiping between cities.
/// Skymoji+ turns all of it off.
@MainActor
@Observable
final class AdsManager: NSObject, FullScreenContentDelegate, BannerViewDelegate {
    /// Debug builds use Google's public test IDs. Release builds use the real ad units from
    /// AdMob (Apps > Skymoji > Ad units); until those are filled in, Release shows no ads at all.
    /// The App ID lives in Info.plist as GADApplicationIdentifier.
    enum AdUnit {
        #if DEBUG
        static let homeBanner = "ca-app-pub-3940256099942544/2934735716"
        static let forecastCard = "ca-app-pub-3940256099942544/2934735716"
        static let citySwipe = "ca-app-pub-3940256099942544/4411468910"
        #else
        static let homeBanner = ""
        static let forecastCard = ""
        static let citySwipe = ""
        #endif

        static var isConfigured: Bool {
            !homeBanner.isEmpty && !forecastCard.isEmpty && !citySwipe.isEmpty
        }
    }

    /// Full-screen ad rules, to keep within AdMob policy and keep people happy:
    /// never in the first session, at most one every 3 minutes, and only after a few swipes.
    enum Interstitial {
        static let swipesBetweenAds = 4
        static let minimumInterval: TimeInterval = 3 * 60
    }

    /// True once consent is settled and the SDK has started.
    private(set) var isReady = false
    private(set) var isShowingFullScreenAd = false
    /// True once the home banner has an ad, so the page only makes room for it then.
    private(set) var isHomeBannerLoaded = false
    /// Created once and reused, so page re-renders never rebuild its web view.
    @ObservationIgnored private(set) var homeBanner: BannerView?

    #if DEBUG
    /// Debug builds start with ads off so launching from Xcode stays fast; the 🐞 menu turns them on.
    static let debugAdsEnabledKey = "debug.adsEnabled"
    #endif

    @ObservationIgnored private var started = false
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var swipesSinceAd = 0
    @ObservationIgnored private var lastFullScreenAd: Date?
    @ObservationIgnored private var launchCount = 0
    @ObservationIgnored private var loadAttempts = 0
    @ObservationIgnored private var isLoadingInterstitial = false
    @ObservationIgnored private let logger = Logger(subsystem: "EmojiWeather", category: "Ads")

    private static let launchCountKey = "ads.launchCount"

    /// Call once the first weather is on screen. Waits a few seconds so launch stays smooth,
    /// shows Google's consent form where the law requires it (EU/UK), then starts the SDK.
    /// The SDK does heavy main-thread setup, so it must never run during launch.
    func start(after delay: Duration = .seconds(3)) async {
        guard !started, AdUnit.isConfigured else { return }
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: Self.debugAdsEnabledKey) else { return }
        #endif
        started = true

        launchCount = UserDefaults.standard.integer(forKey: Self.launchCountKey) + 1
        UserDefaults.standard.set(launchCount, forKey: Self.launchCountKey)

        try? await Task.sleep(for: delay)

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            logger.error("Consent failed: \(error.localizedDescription, privacy: .public)")
        }
        guard ConsentInformation.shared.canRequestAds else { return }

        // Starting the SDK does a lot of synchronous setup, so keep it off the main thread.
        await Task.detached(priority: .utility) {
            _ = await MobileAds.shared.start()
        }.value
        isReady = true
        loadHomeBanner()
        // The full-screen ad loads after the first swipe, not at launch.
    }

    private func loadHomeBanner() {
        guard homeBanner == nil else { return }
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdUnit.homeBanner
        banner.delegate = self
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        banner.load(Request())
        homeBanner = banner
    }

    /// Call when the user swipes to another city.
    func cityPageChanged(hasPlus: Bool) {
        guard isReady, !hasPlus, launchCount > 1 else { return }
        swipesSinceAd += 1
        if interstitial == nil { Task { await loadInterstitial() } }

        let cooledDown = lastFullScreenAd.map { Date.now.timeIntervalSince($0) > Interstitial.minimumInterval } ?? true
        guard swipesSinceAd >= Interstitial.swipesBetweenAds, cooledDown, let ad = interstitial else { return }

        swipesSinceAd = 0
        lastFullScreenAd = .now
        interstitial = nil
        isShowingFullScreenAd = true
        ad.fullScreenContentDelegate = self
        ad.present(from: nil)
    }

    /// Loads the next full-screen ad, retrying with a growing delay when there's no fill or
    /// the SDK isn't fully ready yet (it can report "Invalid request" right after startup).
    private func loadInterstitial() async {
        guard interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }
        while loadAttempts < 5 {
            loadAttempts += 1
            do {
                interstitial = try await InterstitialAd.load(with: AdUnit.citySwipe, request: Request())
                logger.info("Interstitial loaded")
                loadAttempts = 0
                return
            } catch {
                logger.error("Interstitial failed to load (try \(self.loadAttempts)): \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(10 * loadAttempts))
            }
        }
        loadAttempts = 0
    }

    // MARK: - BannerViewDelegate

    nonisolated func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        Task { @MainActor in
            self.logger.info("Home banner loaded")
            self.isHomeBannerLoaded = true
        }
    }

    nonisolated func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.logger.error("Home banner failed: \(message, privacy: .public)")
        }
    }

    // MARK: - FullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            self.isShowingFullScreenAd = false
            await self.loadInterstitial()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            self.isShowingFullScreenAd = false
            await self.loadInterstitial()
        }
    }
}
