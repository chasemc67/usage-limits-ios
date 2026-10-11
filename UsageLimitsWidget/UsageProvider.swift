import Foundation
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshots: [ServiceKind: ServiceSnapshot]
    let configuration: UsageConfigurationIntent
    /// Use-it-or-lose-it nudges the user dismissed in the app (`UseItNudge.dismissalKey`).
    var dismissedNudges: Set<String> = []
}

struct UsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry.sample(configuration: UsageConfigurationIntent())
    }

    func snapshot(for configuration: UsageConfigurationIntent, in context: Context) async -> UsageEntry {
        let cached = SnapshotStore.loadAll()
        if context.isPreview && cached.values.allSatisfy({ $0.windows.isEmpty }) {
            return UsageEntry.sample(configuration: configuration)
        }
        return UsageEntry(date: Date(), snapshots: cached, configuration: configuration,
                          dismissedNudges: Set(NudgeDismissals.load().keys))
    }

    func timeline(for configuration: UsageConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        let cached = SnapshotStore.loadAll()
        // Live fetch using the shared Keychain; fall back to the cache on timeout/failure
        // (fetchAll already keeps cached windows when a service errors).
        let snapshots = await withTimeout(seconds: 25, fallback: cached) {
            await UsageService.fetchAll()
        }

        let now = Date()
        let dismissed = Set(NudgeDismissals.load(now: now).keys)
        // Several entries with the same data so countdown text stays fresh between reloads.
        let entries = stride(from: 0, to: 20, by: 5).map { minutes in
            UsageEntry(date: now.addingTimeInterval(TimeInterval(minutes * 60)),
                       snapshots: snapshots,
                       configuration: configuration,
                       dismissedNudges: dismissed)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(20 * 60)))
    }
}

// MARK: - Selection

struct FocusItem: Identifiable {
    let snapshot: ServiceSnapshot
    let window: UsageWindow
    var id: String { "\(snapshot.kind.rawValue).\(window.id)" }
    var kind: ServiceKind { snapshot.kind }
}

extension UsageEntry {
    /// Services with data, in canonical order.
    var available: [ServiceSnapshot] {
        ServiceKind.allCases.compactMap { snapshots[$0] }.filter { !$0.windows.isEmpty }
    }

    private var candidateSnapshots: [ServiceSnapshot] {
        if let kind = configuration.service.kind {
            return available.filter { $0.kind == kind }
        }
        return available
    }

    private var candidates: [FocusItem] {
        candidateSnapshots.flatMap { snapshot in
            snapshot.windows.map { FocusItem(snapshot: snapshot, window: $0) }
        }
    }

    /// The single window to feature (small / accessory families).
    var focus: FocusItem? {
        let items = candidates
        switch configuration.window {
        case .mostConstrained:
            return items.max { $0.window.usedPercent < $1.window.usedPercent }
        case .shortest:
            return items.min { lhs, rhs in
                let l = lhs.window.windowSeconds ?? .max, r = rhs.window.windowSeconds ?? .max
                return l == r ? lhs.window.usedPercent > rhs.window.usedPercent : l < r
            }
        case .longest:
            return items.max { lhs, rhs in
                let l = lhs.window.windowSeconds ?? 0, r = rhs.window.windowSeconds ?? 0
                return l == r ? lhs.window.usedPercent < rhs.window.usedPercent : l < r
            }
        }
    }

    /// A provider's snapshot, if it has data.
    func snapshot(for kind: ServiceKind) -> ServiceSnapshot? {
        guard let snapshot = snapshots[kind], !snapshot.windows.isEmpty else { return nil }
        return snapshot
    }

    /// The single highest-used pool across every provider (tagged MAX), if any usage is reported.
    var maxItemID: String? {
        let items = available.flatMap { snapshot in
            snapshot.windows.map { FocusItem(snapshot: snapshot, window: $0) }
        }
        // `max(by:)` keeps the first of equal maxima, so ties go to the first in canonical order.
        guard let top = items.max(by: { $0.window.usedPercent < $1.window.usedPercent }),
              top.window.usedPercent > 0 else { return nil }
        return top.id
    }

    /// Use-it-or-lose-it nudges for providers with data, soonest reset first, minus ones dismissed in the app.
    var nudges: [UseItNudge] {
        UseItNudge
            .nudges(snapshots: snapshots, isSignedIn: { snapshot(for: $0) != nil }, now: date)
            .filter { !dismissedNudges.contains($0.dismissalKey) }
    }

    var lastUpdated: Date? {
        snapshots.values.map(\.fetchedAt).max()
    }

    static func sample(configuration: UsageConfigurationIntent) -> UsageEntry {
        let now = Date()
        let day: TimeInterval = 86_400
        let snapshots: [ServiceKind: ServiceSnapshot] = [
            .cursor: ServiceSnapshot(kind: .cursor, windows: [
                UsageWindow(id: "cursor.auto", label: "Cursor Models (Auto)", usedPercent: 1, resetsAt: now.addingTimeInterval(30 * day)),
                UsageWindow(id: "cursor.api", label: "Other Models (API)", usedPercent: 39, resetsAt: now.addingTimeInterval(30 * day)),
                UsageWindow(id: "cursor.total", label: "Total included", usedPercent: 4, resetsAt: now.addingTimeInterval(30 * day)),
            ], extras: [], fetchedAt: now, error: nil),
            .grokBot: ServiceSnapshot(kind: .grokBot, windows: [
                UsageWindow(id: "grok.weekly", label: "Weekly", usedPercent: 21, resetsAt: now.addingTimeInterval(3 * day), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
            .codex: ServiceSnapshot(kind: .codex, windows: [
                UsageWindow(id: "codex.secondary_window", label: "Weekly", usedPercent: 26, resetsAt: now.addingTimeInterval(6 * day), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
            .claude: ServiceSnapshot(kind: .claude, windows: [
                // Inside the 1h five-hour lead time with 63% left, so the large widget shows its banner.
                UsageWindow(id: "claude.five_hour", label: "5-hour", usedPercent: 37, resetsAt: now.addingTimeInterval(58 * 60), windowSeconds: 18_000),
                UsageWindow(id: "claude.seven_day", label: "Weekly (all models)", usedPercent: 25, resetsAt: now.addingTimeInterval(3 * day), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
        ]
        return UsageEntry(date: now, snapshots: snapshots, configuration: configuration)
    }
}
