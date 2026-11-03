import Foundation
import UIKit
import WatchConnectivity

/// Sends the watch the phone's scene pack, your own emoji (with Genmoji pictures), Skymoji+
/// status, units and clock. The watch keeps its own storage, so it can't read the phone's.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    /// Genmoji already sent, so each picture crosses over once.
    private let sentKey = "watch.sentGenmoji"

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the current settings and any new Genmoji. Cheap to call often.
    func send() {
        DispatchQueue.main.async { self.sendNow() }
    }

    private func sendNow() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(StyleSync.context())

        let ids = StyleSync.genmojiIDs
        var sent = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
        let inFlight = Set(session.outstandingFileTransfers.compactMap {
            $0.file.metadata?[StyleSync.genmojiMetadataKey] as? String
        })
        for id in ids where !sent.contains(id) && !inFlight.contains(id) {
            guard let file = watchSizedFile(for: id) else { continue }
            session.transferFile(file, metadata: [StyleSync.genmojiMetadataKey: id])
            sent.insert(id)
        }
        sent.formIntersection(ids)
        UserDefaults.standard.set(Array(sent), forKey: sentKey)
    }

    /// A small PNG of the Genmoji: plenty for the watch, and quick to send.
    private func watchSizedFile(for id: String) -> URL? {
        guard let picture = GenmojiStore.image(for: id) else { return nil }
        let side: CGFloat = 160
        let scale = min(side / max(picture.size.width, 1), side / max(picture.size.height, 1), 1)
        let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            picture.draw(in: CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("genmoji-\(id).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func forget(_ id: String) {
        DispatchQueue.main.async {
            var sent = Set(UserDefaults.standard.stringArray(forKey: self.sentKey) ?? [])
            sent.remove(id)
            UserDefaults.standard.set(Array(sent), forKey: self.sentKey)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        send()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: start again with it.
        DispatchQueue.main.async { UserDefaults.standard.removeObject(forKey: self.sentKey) }
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if !session.isWatchAppInstalled {
            // A fresh install of the watch app will need every picture again.
            DispatchQueue.main.async { UserDefaults.standard.removeObject(forKey: self.sentKey) }
        }
        send()
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard error != nil, let id = fileTransfer.file.metadata?[StyleSync.genmojiMetadataKey] as? String else { return }
        forget(id)
        send()
    }
}
