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
    /// What the last entitlement check saw, for the debug menu.
    private(set) var entitlementNotes: [String] = []
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
                    await self?.apply(transaction)
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

    enum PurchaseOutcome { case purchased, cancelled, pending, unverified }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        AppAnalytics.log(.purchaseStarted, ["plan": product.id])
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                logger.error("Purchase of \(product.id, privacy: .public) failed verification")
                return .unverified
            }
            // Unlock straight from the transaction: Transaction.currentEntitlements can lag
            // a moment behind a new purchase, and reading it first left Plus locked.
            apply(transaction)
            await transaction.finish()
            await refreshEntitlements()
            AppAnalytics.log(.purchaseCompleted, ["plan": product.id])
            return .purchased
        case .pending:
            // Ask to Buy or a payment that needs approval: Transaction.updates unlocks it later.
            logger.info("Purchase of \(product.id, privacy: .public) is pending approval")
            return .pending
        case .userCancelled:
            // "You're already subscribed" can come back as a cancel; pick up that subscription.
            await refreshEntitlements()
            return hasPlus ? .purchased : .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// What Restore Purchases found, for the alert in Settings. Test builds (Xcode and sandbox)
    /// also list the raw entitlements so a TestFlight build can show why Plus is off.
    var restoreSummary: String {
        var text = hasPlus
            ? String(localized: "Skymoji+ is active. Thank you!")
            : String(localized: "No active Skymoji+ subscription was found for this Apple Account.")
        let isTest = entitlementNotes.contains { $0.contains("Sandbox") || $0.contains("Xcode") || $0.contains("UNVERIFIED") }
        #if DEBUG
        let showDetails = true
        #else
        let showDetails = isTest
        #endif
        if showDetails { text += "\n\n" + entitlementNotes.joined(separator: "\n") }
        return text
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Whether a transaction still grants Plus: not refunded and not expired.
    private static func isActive(_ transaction: Transaction) -> Bool {
        guard ProductID.all.contains(transaction.productID), transaction.revocationDate == nil else { return false }
        if let expiration = transaction.expirationDate { return expiration > .now }
        return true
    }

    /// Adds or removes one transaction's product right away.
    private func apply(_ transaction: Transaction) {
        if Self.isActive(transaction) {
            purchasedProductIDs.insert(transaction.productID)
            lastPurchaseAt = .now
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }
    }

    /// When a purchase last unlocked Plus here, so a lagging entitlements read right after it
    /// can't lock the app again.
    @ObservationIgnored private var lastPurchaseAt: Date?

    func refreshEntitlements() async {
        var owned = Set<String>()
        var notes: [String] = []
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                let active = Self.isActive(transaction)
                notes.append("\(transaction.productID) verified, expires \(transaction.expirationDate?.formatted() ?? "never"), revoked \(transaction.revocationDate != nil), active \(active), env \(transaction.environment.rawValue)")
                if active { owned.insert(transaction.productID) }
            case .unverified(let transaction, let error):
                notes.append("\(transaction.productID) UNVERIFIED: \(error)")
            }
        }
        logger.info("Entitlements: \(notes.isEmpty ? "none" : notes.joined(separator: " | "), privacy: .public)")
        entitlementNotes = notes.isEmpty ? ["No entitlements"] : notes
        if owned.isEmpty, let lastPurchaseAt, Date.now.timeIntervalSince(lastPurchaseAt) < 120 {
            // Just bought: keep Plus and check again shortly.
            logger.info("Entitlements empty right after a purchase; keeping Plus and retrying")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                await self?.refreshEntitlements()
            }
            return
        }
        purchasedProductIDs = owned
    }
}
