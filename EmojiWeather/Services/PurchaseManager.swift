import Foundation
import Observation
import os
import StoreKit
import WidgetKit

/// What Skymoji+ unlocks. The paywall lists these, and the app checks them through
/// `PurchaseManager` so the split between free and paid lives in one place.
enum PlusFeature: CaseIterable, Identifiable {
    case noAds
    case unlimitedCities
    case widgets
    case weatherMap
    case scenePacks
    case customEmoji
    case cleanShareClips

    var id: Self { self }

    var emoji: String {
        switch self {
        case .noAds: "🙅"
        case .unlimitedCities: "🌍"
        case .widgets: "🧩"
        case .weatherMap: "🗺️"
        case .scenePacks: "🎃"
        case .customEmoji: "🎨"
        case .cleanShareClips: "🎬"
        }
    }

    var title: String {
        switch self {
        case .noAds: String(localized: "No ads, ever")
        case .unlimitedCities: String(localized: "Unlimited cities")
        case .widgets: String(localized: "Home and Lock Screen widgets")
        case .weatherMap: String(localized: "Emoji weather map")
        case .scenePacks: String(localized: "Seasonal scene packs")
        case .customEmoji: String(localized: "Pick your own weather emoji")
        case .cleanShareClips: String(localized: "Share clips without the watermark")
        }
    }
}

/// Skymoji+ purchases with StoreKit 2. Entitlements are checked on device, so there's no
/// receipt server. In Xcode, the `EmojiWeather.storekit` file lets you test purchases in the
/// simulator before the products exist in App Store Connect.
@MainActor
@Observable
final class PurchaseManager {
    static let freeCityLimit = 3

    enum ProductID {
        static let monthly = "com.longsview.EmojiWeather.plus.monthly"
        static let yearly = "com.longsview.EmojiWeather.plus.yearly"
        static let all = [monthly, yearly]
    }

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = [] {
        didSet { syncPlusStatus() }
    }
    /// Flipped from the debug menu to test both tiers without buying anything.
    var debugUnlock = false {
        didSet { syncPlusStatus() }
    }

    var hasPlus: Bool { debugUnlock || !purchasedProductIDs.isEmpty }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "EmojiWeather", category: "Purchases")

    init() {
        // Purchases made on another device, renewals, refunds and Ask to Buy approvals.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task { await loadProducts() }
    }

    /// Scenes, widgets and the watch use packs and custom emoji only while Plus is active.
    private func syncPlusStatus() {
        guard SceneStyle.plusActive != hasPlus else { return }
        SceneStyle.plusActive = hasPlus
        WidgetCenter.shared.reloadAllTimelines()
        WatchSync.shared.send()
    }

    func canAddCity(currentCount: Int) -> Bool {
        hasPlus || currentCount < Self.freeCityLimit
    }

    func isUnlocked(_ feature: PlusFeature) -> Bool {
        hasPlus
    }

    func product(_ id: String) -> Product? {
        products.first { $0.id == id }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.all)
        } catch {
            logger.error("Loading products failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshEntitlements()
    }

    /// Returns true when the purchase went through.
    func purchase(_ product: Product) async throws -> Bool {
        AppAnalytics.log(.purchaseStarted, ["plan": product.id])
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            await refreshEntitlements()
            AppAnalytics.log(.purchaseCompleted, ["plan": product.id])
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                owned.insert(transaction.productID)
            }
        }
        purchasedProductIDs = owned
    }
}
