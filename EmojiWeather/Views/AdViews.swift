import GoogleMobileAds
import os
import SwiftUI
import UIKit

/// Shows a banner the AdsManager already created and loaded.
struct ExistingBannerView: UIViewRepresentable {
    let banner: BannerView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        banner.removeFromSuperview()
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A fixed-size AdMob banner.
struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    let size: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Logs fills and failures so a slow fill can be told apart from an error.
    final class Coordinator: NSObject, BannerViewDelegate {
        private let logger = Logger(subsystem: "EmojiWeather", category: "Ads")

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            logger.info("Banner loaded: \(bannerView.adUnitID ?? "", privacy: .public)")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            logger.error("Banner failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The small ad near the bottom of the current-location page, with a way out to EmojiWeather+.
struct BannerAdWithUpsell: View {
    var onRemoveAds: () -> Void

    @Environment(AdsManager.self) private var ads
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.skyMode) private var sky

    var body: some View {
        if ads.isHomeBannerLoaded, !purchases.hasPlus, let banner = ads.homeBanner {
            VStack(spacing: 4) {
                ExistingBannerView(banner: banner)
                    .frame(width: 320, height: 50)
                    .clipShape(.rect(cornerRadius: 10))
                Button(action: onRemoveAds) {
                    Text("Remove ads with EmojiWeather+")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(sky.textColor.opacity(0.6))
                }
            }
        }
    }
}

/// An ad styled like the other forecast cards, for the swipe-up sheet.
struct ForecastAdCard: View {
    @Environment(AdsManager.self) private var ads
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        if ads.isReady, !purchases.hasPlus {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ad")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                BannerAdView(adUnitID: AdsManager.AdUnit.forecastCard, size: AdSizeMediumRectangle)
                    .frame(width: 300, height: 250)
                    .clipShape(.rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.black.opacity(0.045), in: .rect(cornerRadius: 24))
        }
    }
}
