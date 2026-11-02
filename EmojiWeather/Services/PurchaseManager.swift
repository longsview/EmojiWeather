import Foundation
import Observation

/// What EmojiWeather+ unlocks. The paywall lists these, and the app checks them through
/// `PurchaseManager` so the split between free and paid lives in one place.
enum PlusFeature: CaseIterable, Identifiable {
    case unlimitedCities
    case widgets
    case scenePacks
    case customEmoji
    case cleanShareClips

    var id: Self { self }

    var emoji: String {
        switch self {
        case .unlimitedCities: "🌍"
        case .widgets: "🧩"
        case .scenePacks: "🎃"
        case .customEmoji: "🎨"
        case .cleanShareClips: "🎬"
        }
    }

    var title: String {
        switch self {
        case .unlimitedCities: "Unlimited cities"
        case .widgets: "Home and Lock Screen widgets"
        case .scenePacks: "Seasonal scene packs, new every month"
        case .customEmoji: "Pick your own emoji for any weather"
        case .cleanShareClips: "Share clips without the watermark"
        }
    }
}

/// Tracks whether the user has EmojiWeather+.
///
/// StoreKit 2 isn't wired up yet; that comes in a follow-up. Until then `hasPlus` is false, and in
/// debug builds it can be flipped from the home screen's debug menu to test both tiers.
@MainActor
@Observable
final class PurchaseManager {
    static let freeCityLimit = 3

    var hasPlus = false

    func canAddCity(currentCount: Int) -> Bool {
        hasPlus || currentCount < Self.freeCityLimit
    }

    func isUnlocked(_ feature: PlusFeature) -> Bool {
        hasPlus
    }
}
