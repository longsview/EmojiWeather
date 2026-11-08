import Foundation
import UserNotifications

/// Shows reminders while the app is open, and opens the quiz when one is tapped.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    /// Set at launch. Tapping a reminder asks it to open the quiz.
    @MainActor weak var quiz: QuizStore?

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let url = response.notification.request.content.userInfo["url"] as? String
        guard url == QuizStore.quizURL.absoluteString else { return }
        await MainActor.run { quiz?.openRequested = true }
    }
}
