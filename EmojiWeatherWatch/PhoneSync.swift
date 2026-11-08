import Foundation
import WatchConnectivity
import WidgetKit

/// Receives the phone's scene pack, your own emoji (with Genmoji pictures), Skymoji+ status,
/// units and clock, and saves them where the watch app and complications read them.
final class PhoneSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneSync()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func apply(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        // Settings drive views, so write them on the main thread.
        let box = ContextBox(context: context)
        DispatchQueue.main.async {
            StyleSync.apply(box.context)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let id = file.metadata?[StyleSync.genmojiMetadataKey] as? String else { return }
        // The file is deleted when this returns, so copy it now.
        GenmojiStore.store(fileAt: file.fileURL, id: id)
        DispatchQueue.main.async {
            let defaults = SharedStore.defaults
            defaults.set(defaults.integer(forKey: StyleSync.genmojiVersionKey) + 1, forKey: StyleSync.genmojiVersionKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// Carries the context dictionary across to the main queue.
private struct ContextBox: @unchecked Sendable {
    let context: [String: Any]
}
