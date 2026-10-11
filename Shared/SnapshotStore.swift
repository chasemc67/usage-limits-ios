import Foundation

/// Persists the last-known snapshots in the app-group UserDefaults so the widget
/// can render cached values and the app can show "last updated".
enum SnapshotStore {
    private static let key = "snapshots.v1"

    static func loadAll() -> [ServiceKind: ServiceSnapshot] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ServiceSnapshot].self, from: data) else {
            return [:]
        }
        var result: [ServiceKind: ServiceSnapshot] = [:]
        for (raw, snapshot) in decoded {
            if let kind = ServiceKind(rawValue: raw) {
                result[kind] = snapshot
            }
        }
        return result
    }

    static func saveAll(_ snapshots: [ServiceKind: ServiceSnapshot]) {
        var encodable: [String: ServiceSnapshot] = [:]
        for (kind, snapshot) in snapshots {
            encodable[kind.rawValue] = snapshot
        }
        if let data = try? JSONEncoder().encode(encodable) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    /// Merges fresh results onto the stored ones (keeping cached data on failure) and saves.
    @discardableResult
    static func merge(_ fresh: [ServiceSnapshot]) -> [ServiceKind: ServiceSnapshot] {
        var all = loadAll()
        for snapshot in fresh {
            all[snapshot.kind] = snapshot.merged(onto: all[snapshot.kind])
        }
        saveAll(all)
        return all
    }

    static func remove(_ kinds: [ServiceKind]) {
        var all = loadAll()
        for kind in kinds {
            all.removeValue(forKey: kind)
        }
        saveAll(all)
    }

    static var lastUpdated: Date? {
        loadAll().values.map(\.fetchedAt).max()
    }
}
