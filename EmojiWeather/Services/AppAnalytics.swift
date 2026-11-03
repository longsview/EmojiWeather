import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
import FirebaseCore
#endif
import WidgetKit

/// Firebase Analytics events for the iPhone app. Nothing is logged until Firebase is configured
/// (see `CrashReporting`), and Debug builds don't send anything. No names, places or
/// coordinates are ever sent: only what kind of thing happened.
enum AppAnalytics {
    enum Event: String {
        case cityAdded = "city_added"
        case cityRemoved = "city_removed"
        case forecastOpened = "forecast_opened"
        case mapOpened = "map_opened"
        case shareExported = "share_exported"
        case quizOpened = "quiz_opened"
        case quizFinished = "quiz_finished"
        case guessLocked = "tomorrow_guess_locked"
        case reminderEnabled = "reminder_enabled"
        case paywallViewed = "paywall_viewed"
        case purchaseStarted = "purchase_started"
        case purchaseCompleted = "purchase_completed"
        case scenePackChosen = "scene_pack_chosen"
        case customEmojiSet = "custom_emoji_set"
    }

    /// Call once at launch, after `CrashReporting.start()`.
    static func start() {
        #if canImport(FirebaseAnalytics)
        guard FirebaseApp.app() != nil else { return }
        #if DEBUG
        Analytics.setAnalyticsCollectionEnabled(false)
        #else
        Analytics.setAnalyticsCollectionEnabled(true)
        #endif
        #endif
    }

    static func log(_ event: Event, _ parameters: [String: Any] = [:]) {
        #if canImport(FirebaseAnalytics)
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
        #endif
    }

    static func setUserProperty(_ value: String?, forName name: String) {
        #if canImport(FirebaseAnalytics)
        guard FirebaseApp.app() != nil else { return }
        Analytics.setUserProperty(value, forName: name)
        #endif
    }

    /// How many Home and Lock Screen widgets are set up, and whether Skymoji+ is active,
    /// so reports can be split by them.
    static func updateUserProperties(hasPlus: Bool) {
        setUserProperty(hasPlus ? "yes" : "no", forName: "has_plus")
        WidgetCenter.shared.getCurrentConfigurations { result in
            let count = (try? result.get().count) ?? 0
            setUserProperty(String(count), forName: "widget_count")
        }
    }
}
