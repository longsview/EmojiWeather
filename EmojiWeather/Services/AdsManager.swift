import Foundation
import GoogleMobileAds
import Observation
import os
import UIKit
import UserMessagingPlatform

/// Google AdMob for the free tier: a small banner on the current-location page, a card in the
/// forecast sheet, and an occasional full-screen ad when swiping between cities.
/// EmojiWeather+ turns all of it off.
@MainActor
@Observable
final class AdsManager: NSObject, FullScreenContentDelegate {
    /// Google's public test IDs. Swap in the real ones from AdMob before release
    /// (the App ID lives in Info.plist as GADApplicationIdentifier).
    enum AdUnit {
        static let homeBanner = "ca-app-pub-3940256099942544/2934735716"
        static let forecastCard = "ca-app-pub-3940256099942544/2934735716"
        static let citySwipe = "ca-app-pub-3940256099942544/4411468910"
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

    @ObservationIgnored private var started = false
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var swipesSinceAd = 0
    @ObservationIgnored private var lastFullScreenAd: Date?
    @ObservationIgnored private var launchCount = 0
    @ObservationIgnored private let logger = Logger(subsystem: "EmojiWeather", category: "Ads")

    private static let launchCountKey = "ads.launchCount"

    /// Call once at launch. Shows Google's consent form where the law requires it (EU/UK),
    /// then starts the SDK.
    func start() async {
        guard !started else { return }
        started = true

        launchCount = UserDefaults.standard.integer(forKey: Self.launchCountKey) + 1
        UserDefaults.standard.set(launchCount, forKey: Self.launchCountKey)

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            logger.error("Consent failed: \(error.localizedDescription, privacy: .public)")
        }
        guard ConsentInformation.shared.canRequestAds else { return }

        _ = await MobileAds.shared.start()
        isReady = true
        await loadInterstitial()
    }

    /// Call when the user swipes to another city.
    func cityPageChanged(hasPlus: Bool) {
        guard isReady, !hasPlus, launchCount > 1 else { return }
        swipesSinceAd += 1

        let cooledDown = lastFullScreenAd.map { Date.now.timeIntervalSince($0) > Interstitial.minimumInterval } ?? true
        guard swipesSinceAd >= Interstitial.swipesBetweenAds, cooledDown, let ad = interstitial else { return }

        swipesSinceAd = 0
        lastFullScreenAd = .now
        interstitial = nil
        isShowingFullScreenAd = true
        ad.fullScreenContentDelegate = self
        ad.present(from: nil)
    }

    private func loadInterstitial() async {
        do {
            interstitial = try await InterstitialAd.load(with: AdUnit.citySwipe, request: Request())
        } catch {
            logger.error("Interstitial failed to load: \(error.localizedDescription, privacy: .public)")
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
