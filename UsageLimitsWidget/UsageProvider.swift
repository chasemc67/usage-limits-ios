import Foundation
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshots: [ServiceKind: ServiceSnapshot]
    let configuration: UsageConfigurationIntent
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
        return UsageEntry(date: Date(), snapshots: cached, configuration: configuration)
    }

    func timeline(for configuration: UsageConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        let cached = SnapshotStore.loadAll()
        // Live fetch using the shared Keychain; fall back to the cache on timeout/failure
        // (fetchAll already keeps cached windows when a service errors).
        let snapshots = await withTimeout(seconds: 25, fallback: cached) {
            await UsageService.fetchAll()
        }

        let now = Date()
        // Several entries with the same data so countdown text stays fresh between reloads.
        let entries = stride(from: 0, to: 20, by: 5).map { minutes in
            UsageEntry(date: now.addingTimeInterval(TimeInterval(minutes * 60)),
                       snapshots: snapshots,
                       configuration: configuration)
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

    /// Up to `limit` windows for the medium family: the chosen service's windows,
    /// or the most constrained windows across all services.
    func topItems(limit: Int) -> [FocusItem] {
        let items = candidates
        if configuration.service.kind != nil {
            return Array(items.prefix(limit))
        }
        return Array(items.sorted { $0.window.usedPercent > $1.window.usedPercent }.prefix(limit))
    }

    var lastUpdated: Date? {
        snapshots.values.map(\.fetchedAt).max()
    }

    static func sample(configuration: UsageConfigurationIntent) -> UsageEntry {
        let now = Date()
        let snapshots: [ServiceKind: ServiceSnapshot] = [
            .cursor: ServiceSnapshot(kind: .cursor, windows: [
                UsageWindow(label: "Cursor Models (Auto)", usedPercent: 34, resetsAt: now.addingTimeInterval(9 * 86_400)),
                UsageWindow(label: "Other Models (API)", usedPercent: 62, resetsAt: now.addingTimeInterval(9 * 86_400)),
            ], extras: [], fetchedAt: now, error: nil),
            .grokBot: ServiceSnapshot(kind: .grokBot, windows: [
                UsageWindow(label: "Weekly", usedPercent: 18, resetsAt: now.addingTimeInterval(3 * 86_400), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
            .codex: ServiceSnapshot(kind: .codex, windows: [
                UsageWindow(label: "5-hour", usedPercent: 47, resetsAt: now.addingTimeInterval(2 * 3600 + 840), windowSeconds: 18_000),
                UsageWindow(label: "Weekly", usedPercent: 88, resetsAt: now.addingTimeInterval(2 * 86_400), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
            .claude: ServiceSnapshot(kind: .claude, windows: [
                UsageWindow(label: "5-hour", usedPercent: 23, resetsAt: now.addingTimeInterval(3 * 3600), windowSeconds: 18_000),
                UsageWindow(label: "Weekly (all models)", usedPercent: 56, resetsAt: now.addingTimeInterval(4 * 86_400), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
        ]
        return UsageEntry(date: now, snapshots: snapshots, configuration: configuration)
    }
}
