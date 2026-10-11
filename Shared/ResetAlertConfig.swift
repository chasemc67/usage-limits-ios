import Foundation

/// The cadence of a usage window, inferred from its duration or label.
enum ResetWindowKind: Hashable, Sendable {
    case fiveHour
    case weekly
    case monthly
    case other(seconds: Int?)

    /// Prefers the window duration when known; falls back to label hints, then per-service assumptions.
    static func infer(_ window: UsageWindow, service: ServiceKind,
                      config: ResetAlertConfig = .standard) -> ResetWindowKind {
        if let seconds = window.windowSeconds, seconds > 0 {
            let hours = Double(seconds) / 3600
            let days = hours / 24
            if (4.5...5.5).contains(hours) { return .fiveHour }
            if (6.5...7.5).contains(days) { return .weekly }
            if (27...32).contains(days) { return .monthly }
            return .other(seconds: seconds)
        }

        let label = window.label.lowercased()
        if label.contains("5-hour") || label.contains("5 hour") || label.contains("5h") { return .fiveHour }
        if label.contains("week") || label.contains("7-day") || label.contains("7 day") { return .weekly }
        if label.contains("month") { return .monthly }
        if config.assumedMonthlyServices.contains(service) { return .monthly }
        return .other(seconds: nil)
    }
}

/// Thresholds for the "use it or lose it" reset banner.
struct ResetAlertConfig: Sendable {
    /// Only alert when at least this much of the window is unused (0...100).
    var minimumRemainingPercent: Double = 50
    /// How close to reset (seconds) before alerting, per window kind.
    var fiveHourLeadTime: TimeInterval = 3600
    var weeklyLeadTime: TimeInterval = 24 * 3600
    var monthlyLeadTime: TimeInterval = 3 * 24 * 3600
    /// For other window lengths: alert in the last fraction of the window (only if its duration is known).
    var otherWindowLeadFraction: Double = 0.20
    /// Services whose windows are billing cycles even when the API omits the duration (Cursor).
    var assumedMonthlyServices: Set<ServiceKind> = [.cursor]
    /// Maximum number of banners shown at once.
    var maxVisibleAlerts: Int = 2

    static let standard = ResetAlertConfig()

    /// Seconds before reset at which the window starts alerting, or nil if it can't be determined.
    func leadTime(for kind: ResetWindowKind) -> TimeInterval? {
        switch kind {
        case .fiveHour: return fiveHourLeadTime
        case .weekly: return weeklyLeadTime
        case .monthly: return monthlyLeadTime
        case .other(let seconds):
            guard let seconds, seconds > 0 else { return nil }
            return Double(seconds) * otherWindowLeadFraction
        }
    }
}
