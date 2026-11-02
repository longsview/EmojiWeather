import Foundation
import Observation
import SwiftUI // for Array.remove(atOffsets:) and move(fromOffsets:toOffset:)

/// The user's list of saved cities, synced across their devices with the iCloud key-value store.
///
/// The list is small (a few KB at most), so `NSUbiquitousKeyValueStore` is enough and no CloudKit
/// schema or backend is needed. A copy is also kept in `UserDefaults` so the list still works when
/// the user is signed out of iCloud.
@MainActor
@Observable
final class CityStore {
    static let storageKey = "savedCities.v1"

    private(set) var cities: [City] = []

    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore
    @ObservationIgnored private let local: UserDefaults
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(cloud: NSUbiquitousKeyValueStore = .default, local: UserDefaults = .standard) {
        self.cloud = cloud
        self.local = local
        cities = Self.decode(cloud.data(forKey: Self.storageKey))
            ?? Self.decode(local.data(forKey: Self.storageKey))
            ?? []

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                self?.handleExternalChange(reason: reason)
            }
        }

        // Pulls down any changes made on other devices while the app was closed.
        cloud.synchronize()
    }

    // MARK: - Editing

    /// Adds a city unless it's already in the list. Returns false for a duplicate.
    @discardableResult
    func add(_ city: City) -> Bool {
        guard !cities.contains(where: { $0.isSamePlace(as: city) }) else { return false }
        cities.append(city)
        save()
        return true
    }

    func remove(_ city: City) {
        cities.removeAll { $0.id == city.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        cities.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Sync

    private func save() {
        guard let data = try? JSONEncoder().encode(cities) else { return }
        local.set(data, forKey: Self.storageKey)
        cloud.set(data, forKey: Self.storageKey)
    }

    private func handleExternalChange(reason: Int?) {
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange,
             NSUbiquitousKeyValueStoreAccountChange:
            // iCloud is last-writer-wins: take the newest list from the cloud.
            if let remote = Self.decode(cloud.data(forKey: Self.storageKey)) {
                cities = remote
                local.set(cloud.data(forKey: Self.storageKey), forKey: Self.storageKey)
            }
        default:
            // Quota violations can't happen with a list this small; nothing else to do.
            break
        }
    }

    private static func decode(_ data: Data?) -> [City]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([City].self, from: data)
    }
}
