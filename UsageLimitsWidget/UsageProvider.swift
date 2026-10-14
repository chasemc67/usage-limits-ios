import Foundation
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshots: [ServiceKind: ServiceSnapshot]
    /// Service/window selection (Lock Screen families).
    var configuration = UsageConfigurationIntent()
    /// Provider shown by the small Home Screen widget.
    var provider: ProviderChoice = .claude
    /// Use-it-or-lose-it nudges the user dismissed in the app (`UseItNudge.dismissalKey`).
    var dismissedNudges: Set<String> = []
}

/// Shared snapshot/timeline loading for every widget kind.
private enum UsageLoader {
    static func snapshot(isPreview: Bool, configure: (inout UsageEntry) -> Void) -> UsageEntry {
        let cached = SnapshotStore.loadAll()
        var entry: UsageEntry
        if isPreview && cached.values.allSatisfy({ $0.windows.isEmpty }) {
            entry = UsageEntry.sample()
        } else {
            entry = UsageEntry(date: Date(), snapshots: cached,
                               dismissedNudges: Set(NudgeDismissals.load().keys))
        }
        configure(&entry)
        return entry
    }

    static func timeline(configure: (inout UsageEntry) -> Void) async -> Timeline<UsageEntry> {
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
            var entry = UsageEntry(date: now.addingTimeInterval(TimeInterval(minutes * 60)),
                                   snapshots: snapshots,
                                   dismissedNudges: dismissed)
            configure(&entry)
            return entry
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(20 * 60)))
    }
}

/// Lock Screen families (service + window).
struct UsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry.sample()
    }

    func snapshot(for configuration: UsageConfigurationIntent, in context: Context) async -> UsageEntry {
        UsageLoader.snapshot(isPreview: context.isPreview) { $0.configuration = configuration }
    }

    func timeline(for configuration: UsageConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        await UsageLoader.timeline { $0.configuration = configuration }
    }
}

/// Small Home Screen (one provider).
struct ProviderUsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry.sample()
    }

    func snapshot(for configuration: ProviderConfigurationIntent, in context: Context) async -> UsageEntry {
        UsageLoader.snapshot(isPreview: context.isPreview) { $0.provider = configuration.provider }
    }

    func timeline(for configuration: ProviderConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        await UsageLoader.timeline { $0.provider = configuration.provider }
    }
}

/// Medium and large Home Screen (every provider, no configuration).
struct OverviewUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry.sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageLoader.snapshot(isPreview: context.isPreview) { _ in })
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            completion(await UsageLoader.timeline { _ in })
        }
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
    /// Sections with data, in display order (xAI replaces Cursor + Grok Bot on unified accounts).
    var available: [ServiceSnapshot] {
        UnifiedPlan.sectionKinds(snapshots).compactMap { snapshot(for: $0) }
    }

    /// The section that shows `kind`, so saved Cursor / Grok Bot choices land on xAI when unified.
    func section(for kind: ServiceKind) -> ServiceKind {
        UnifiedPlan.section(for: kind, in: snapshots)
    }

    private var candidateSnapshots: [ServiceSnapshot] {
        if let kind = configuration.service.kind.map(section(for:)) {
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

    /// A section's snapshot, if it has data.
    func snapshot(for kind: ServiceKind) -> ServiceSnapshot? {
        guard let snapshot = UnifiedPlan.sectionSnapshot(kind, in: snapshots), !snapshot.windows.isEmpty else { return nil }
        return snapshot
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

    static func sample(provider: ProviderChoice = .claude, unified: Bool = false) -> UsageEntry {
        let now = Date()
        let day: TimeInterval = 86_400
        var snapshots: [ServiceKind: ServiceSnapshot] = [
            .cursor: ServiceSnapshot(kind: .cursor, windows: [
                UsageWindow(id: "cursor.auto", label: "Cursor Models (Auto)", usedPercent: 1, resetsAt: now.addingTimeInterval(30 * day)),
                UsageWindow(id: "cursor.api", label: "Other Models (API)", usedPercent: 39, resetsAt: now.addingTimeInterval(30 * day)),
                UsageWindow(id: "cursor.total", label: "Total included", usedPercent: 4, resetsAt: now.addingTimeInterval(30 * day)),
            ], extras: [], fetchedAt: now, error: nil),
            .grokBot: ServiceSnapshot(kind: .grokBot, windows: [
                UsageWindow(id: "grok.weekly", label: "Weekly", usedPercent: 21, resetsAt: now.addingTimeInterval(3 * day), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
            .codex: ServiceSnapshot(kind: .codex, windows: [
                UsageWindow(id: "codex.secondary_window", label: "Weekly", usedPercent: 70, resetsAt: now.addingTimeInterval(6 * day), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
            .claude: ServiceSnapshot(kind: .claude, windows: [
                // Inside the 1h five-hour lead time with 84% left, so the large widget shows its banner.
                UsageWindow(id: "claude.five_hour", label: "5-hour", usedPercent: 16, resetsAt: now.addingTimeInterval(58 * 60), windowSeconds: 18_000),
                UsageWindow(id: "claude.seven_day", label: "Weekly (all models)", usedPercent: 83, resetsAt: now.addingTimeInterval(3 * day), windowSeconds: 604_800),
                UsageWindow(id: "claude.weekly_scoped.fable", label: "Weekly (Fable only)", usedPercent: 0, resetsAt: now.addingTimeInterval(5 * day), windowSeconds: 604_800),
            ], extras: [], fetchedAt: now, error: nil),
        ]
        if unified {
            let shared = UsageWindow(id: UnifiedPlan.cursorSharedWindowID, label: UnifiedPlan.sharedWindowLabel,
                                     usedPercent: 17, resetsAt: now.addingTimeInterval(3 * day), windowSeconds: 604_800)
            snapshots[.cursor] = ServiceSnapshot(kind: .cursor, windows: [shared], extras: ["Plan: Ultra"],
                                                 fetchedAt: now, error: nil, thirdPartyCents: 1234,
                                                 thirdPartySince: Calendar.current.dateInterval(of: .month, for: now)?.start,
                                                 unified: true)
            snapshots[.grokBot] = nil
        }
        return UsageEntry(date: now, snapshots: snapshots, provider: provider)
    }
}
