import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshots: [ServiceKind: ServiceSnapshot]
    @Published private(set) var signedIn: [ServiceKind: Bool] = [:]
    @Published private(set) var refreshing: Set<ServiceKind> = []
    @Published var sheetKind: ServiceKind?

    private var lastRefresh: Date?

    init() {
        snapshots = SnapshotStore.loadAll()
        reloadAuthState()
    }

    var lastUpdated: Date? {
        snapshots.values.map(\.fetchedAt).max()
    }

    var isRefreshingAny: Bool { !refreshing.isEmpty }

    var anySignedIn: Bool { signedIn.values.contains(true) }

    func isSignedIn(_ kind: ServiceKind) -> Bool { signedIn[kind] ?? false }

    func isRefreshing(_ kind: ServiceKind) -> Bool { refreshing.contains(kind) }

    func reloadAuthState() {
        var state: [ServiceKind: Bool] = [:]
        for kind in ServiceKind.allCases {
            state[kind] = TokenStore.signedIn(kind)
        }
        signedIn = state
    }

    func refreshAll() async {
        await refresh(ServiceKind.allCases)
    }

    func refreshIfStale() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 120 { return }
        await refreshAll()
    }

    func refresh(_ kinds: [ServiceKind]) async {
        reloadAuthState()
        let targets = kinds.filter { isSignedIn($0) && !refreshing.contains($0) }
        guard !targets.isEmpty else { return }

        refreshing.formUnion(targets)
        lastRefresh = Date()
        let result = await UsageService.fetchAll(targets)
        snapshots = result
        refreshing.subtract(targets)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Called after any sign-in flow stores credentials.
    func didSignIn(_ kind: ServiceKind) {
        reloadAuthState()
        let group = kind.credentialGroup
        Task { await refresh(group) }
    }

    func signOut(_ kind: ServiceKind) {
        let group = kind.credentialGroup
        TokenStore.signOut(kind)
        SnapshotStore.remove(group)
        WebSessionCleaner.clear(for: kind)
        snapshots = SnapshotStore.loadAll()
        reloadAuthState()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
