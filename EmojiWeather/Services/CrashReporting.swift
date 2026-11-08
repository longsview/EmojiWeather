import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseCrashlytics
#endif

/// Firebase Crashlytics for the iPhone and watch apps. It starts only when the target has its
/// GoogleService-Info.plist (downloaded from the Firebase console), so builds work before that.
/// Debug builds don't send reports, so crashes while developing don't clutter the dashboard.
enum CrashReporting {
    static func start() {
        #if canImport(FirebaseCore)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
        #endif
    }
}
