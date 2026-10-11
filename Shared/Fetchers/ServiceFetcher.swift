import Foundation

/// Each fetcher reads its own credentials from the Keychain and never throws:
/// failures are captured in `ServiceSnapshot.error`.
protocol ServiceFetcher: Sendable {
    func fetch() async -> ServiceSnapshot
}

enum UsageService {
    static func fetcher(for kind: ServiceKind) -> any ServiceFetcher {
        switch kind {
        case .cursor: return CursorFetcher()
        case .grokBot: return GrokBotFetcher()
        case .codex: return CodexFetcher()
        case .claude: return ClaudeFetcher()
        }
    }

    /// Fetches the given (signed-in) services concurrently, merges into the shared
    /// cache, and returns the full cached dictionary.
    static func fetchAll(_ kinds: [ServiceKind] = ServiceKind.allCases) async -> [ServiceKind: ServiceSnapshot] {
        let targets = kinds.filter { TokenStore.signedIn($0) }
        guard !targets.isEmpty else { return SnapshotStore.loadAll() }

        let fresh = await withTaskGroup(of: ServiceSnapshot.self, returning: [ServiceSnapshot].self) { group in
            for kind in targets {
                group.addTask { await UsageService.fetcher(for: kind).fetch() }
            }
            var results: [ServiceSnapshot] = []
            for await snapshot in group {
                results.append(snapshot)
            }
            return results
        }

        // A cancelled refresh (e.g. widget timeout) shouldn't overwrite good cached data.
        if Task.isCancelled { return SnapshotStore.loadAll() }
        return SnapshotStore.merge(fresh)
    }
}

/// Runs `operation`, returning `fallback` if it doesn't finish within `seconds`.
func withTimeout<T: Sendable>(seconds: Double,
                              fallback: T,
                              _ operation: @escaping @Sendable () async -> T) async -> T {
    await withTaskGroup(of: T?.self, returning: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next()
        group.cancelAll()
        if let first, let value = first {
            return value
        }
        return fallback
    }
}
