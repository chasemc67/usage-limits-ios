import Foundation

/// A "use it or lose it" reminder: a window that resets soon with lots of quota left.
struct UseItNudge: Identifiable, Hashable {
    let kind: ServiceKind
    let window: UsageWindow
    let resetsAt: Date
    let timeToReset: TimeInterval
    /// Whether the service reports more than one window, so the label is needed to tell them apart.
    let showsWindowLabel: Bool

    var id: String { dismissalKey }

    var remainingPercent: Double { window.remainingPercent }

    /// serviceKind + window id + resetsAt (to the minute, since some APIs jitter by sub-seconds).
    var dismissalKey: String {
        let minute = Int((resetsAt.timeIntervalSince1970 / 60).rounded())
        return "\(kind.rawValue)|\(window.id)|\(minute)"
    }

    /// "Grok Bot: 80% left, resets in 18h" or "Claude (Weekly Opus): 62% left, resets in 18h".
    func message(now: Date) -> String {
        let countdown = Self.humanCountdown(resetsAt.timeIntervalSince(now))
        let name = showsWindowLabel ? "\(kind.displayName) (\(window.label))" : kind.displayName
        return "\(name): \(Fmt.percent(remainingPercent)) left, resets in \(countdown)"
    }

    /// "2d 5h", "18h", "1h 20m", "42m", "<1m".
    static func humanCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours >= 3 { return "\(hours)h" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Nudges for every qualifying window across signed-in services, soonest reset first.
    static func nudges(snapshots: [ServiceKind: ServiceSnapshot],
                       isSignedIn: (ServiceKind) -> Bool,
                       now: Date,
                       config: ResetAlertConfig = .standard) -> [UseItNudge] {
        var result: [UseItNudge] = []
        for kind in ServiceKind.allCases where isSignedIn(kind) {
            guard let snapshot = snapshots[kind] else { continue }
            for window in snapshot.windows {
                guard let resetsAt = window.resetsAt,
                      let leadTime = config.leadTime(for: ResetWindowKind.infer(window, service: kind, config: config))
                else { continue }
                let timeToReset = resetsAt.timeIntervalSince(now)
                guard timeToReset > 0,
                      timeToReset <= leadTime,
                      window.remainingPercent >= config.minimumRemainingPercent else { continue }
                result.append(UseItNudge(kind: kind, window: window, resetsAt: resetsAt,
                                         timeToReset: timeToReset,
                                         showsWindowLabel: snapshot.windows.count > 1))
            }
        }
        return result.sorted {
            if $0.timeToReset != $1.timeToReset { return $0.timeToReset < $1.timeToReset }
            return $0.remainingPercent > $1.remainingPercent
        }
    }
}

/// Persists dismissed nudges in the app-group defaults, pruning ones whose window has reset.
enum NudgeDismissals {
    private static let key = "useItNudgeDismissals"

    static func load(now: Date = Date()) -> [String: Date] {
        guard let raw = AppGroup.defaults.dictionary(forKey: key) as? [String: Double] else { return [:] }
        return raw
            .mapValues { Date(timeIntervalSince1970: $0) }
            .filter { $0.value > now }
    }

    static func save(_ dismissals: [String: Date]) {
        AppGroup.defaults.set(dismissals.mapValues(\.timeIntervalSince1970), forKey: key)
    }
}
