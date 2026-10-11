import Foundation

/// A "use it or lose it" reminder: a window that resets soon with lots of quota left.
struct UseItNudge: Identifiable, Hashable {
    let kind: ServiceKind
    let window: UsageWindow
    let resetsAt: Date
    let timeToReset: TimeInterval

    /// Show when the window is in its last 15% and at least 40% is unused.
    static let resetFraction = 0.15
    static let minimumRemainingPercent = 40.0

    var id: String { dismissalKey }

    var remainingPercent: Double { window.remainingPercent }

    /// serviceKind + window label + resetsAt (to the minute, since some APIs jitter by sub-seconds).
    var dismissalKey: String {
        let minute = Int((resetsAt.timeIntervalSince1970 / 60).rounded())
        return "\(kind.rawValue)|\(window.label)|\(minute)"
    }

    /// "Claude weekly (all models) resets in 18h — 76% left. Use it!"
    func message(now: Date) -> String {
        let countdown = Self.humanCountdown(resetsAt.timeIntervalSince(now))
        return "\(kind.displayName) \(sentenceLabel) resets in \(countdown) — \(Fmt.percent(remainingPercent)) left. Use it!"
    }

    /// Lowercases a leading capitalized word ("Weekly Opus" -> "weekly Opus") but keeps acronyms.
    private var sentenceLabel: String {
        let label = window.label
        guard let first = label.first, label.count > 1,
              label[label.index(after: label.startIndex)].isLowercase else { return label }
        return first.lowercased() + label.dropFirst()
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
                       now: Date) -> [UseItNudge] {
        var result: [UseItNudge] = []
        for kind in ServiceKind.allCases where isSignedIn(kind) {
            guard let snapshot = snapshots[kind] else { continue }
            for window in snapshot.windows {
                guard let resetsAt = window.resetsAt,
                      let windowSeconds = window.windowSeconds, windowSeconds > 0 else { continue }
                let timeToReset = resetsAt.timeIntervalSince(now)
                guard timeToReset > 0,
                      timeToReset <= Double(windowSeconds) * resetFraction,
                      window.remainingPercent >= minimumRemainingPercent else { continue }
                result.append(UseItNudge(kind: kind, window: window, resetsAt: resetsAt, timeToReset: timeToReset))
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
