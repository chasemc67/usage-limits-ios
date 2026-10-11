import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshots: [ServiceKind: ServiceSnapshot]
    @Published private(set) var signedIn: [ServiceKind: Bool] = [:]
    @Published private(set) var refreshing: Set<ServiceKind> = []
    @Published var sheetKind: ServiceKind?
    /// Dismissed "use it or lose it" nudges: nudge key -> the reset date it applies to.
    @Published private(set) var dismissedNudges: [String: Date]

    private var lastRefresh: Date?

    init() {
        snapshots = SnapshotStore.loadAll()
        dismissedNudges = NudgeDismissals.load()
        reloadAuthState()
        #if DEBUG
        if Self.demoMode { seedDemo() }
        #endif
    }

    #if DEBUG
    /// Debug-only screenshot mode: launch with `-TMXDemo` to show sample data without signing in.
    static var demoMode: Bool { ProcessInfo.processInfo.arguments.contains("-TMXDemo") }

    private func seedDemo() {
        let now = Date()
        let d: Double = 86_400
        let s: [ServiceKind: ServiceSnapshot] = [
            .grokBot: ServiceSnapshot(kind: .grokBot, windows: [
                UsageWindow(label: "Weekly", usedPercent: 20, resetsAt: now.addingTimeInterval(3*d + 22*3600), windowSeconds: 604_800)],
                extras: ["Plan: Ultra", "Cursor plan: ultra", "On-demand: enabled"], fetchedAt: now, error: nil),
            .codex: ServiceSnapshot(kind: .codex, windows: [
                UsageWindow(label: "Weekly", usedPercent: 0, resetsAt: now.addingTimeInterval(7*d), windowSeconds: 604_800)],
                extras: ["Plan: Plus", "Credits: 100", "Reset credits available: 2"], fetchedAt: now, error: nil),
            .claude: ServiceSnapshot(kind: .claude, windows: [
                UsageWindow(label: "5-hour", usedPercent: 25, resetsAt: now.addingTimeInterval(42*60), windowSeconds: 18_000),
                UsageWindow(label: "Weekly (all models)", usedPercent: 24, resetsAt: now.addingTimeInterval(3*d + 19*3600), windowSeconds: 604_800)],
                extras: ["Extra usage: off"], fetchedAt: now, error: nil),
            .cursor: ServiceSnapshot(kind: .cursor, windows: [
                UsageWindow(label: "Cursor Models", usedPercent: 38, resetsAt: now.addingTimeInterval(31*d)),
                UsageWindow(label: "Other Models", usedPercent: 12, resetsAt: now.addingTimeInterval(31*d)),
                UsageWindow(label: "Total included", usedPercent: 27, resetsAt: now.addingTimeInterval(31*d))],
                extras: ["Plan: Ultra", "On-demand: $0.00 spent"], fetchedAt: now, error: nil),
        ]
        SnapshotStore.saveAll(s)
        snapshots = s
        var st: [ServiceKind: Bool] = [:]
        for k in ServiceKind.allCases { st[k] = true }
        signedIn = st
    }
    #endif

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
        #if DEBUG
        if Self.demoMode { return }
        #endif
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

    func isDismissed(_ nudge: UseItNudge) -> Bool {
        dismissedNudges[nudge.dismissalKey] != nil
    }

    /// Hides a nudge until its window resets; a new `resetsAt` produces a new key and re-shows it.
    func dismiss(_ nudge: UseItNudge) {
        var updated = dismissedNudges.filter { $0.value > Date() }
        updated[nudge.dismissalKey] = nudge.resetsAt
        dismissedNudges = updated
        NudgeDismissals.save(updated)
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
