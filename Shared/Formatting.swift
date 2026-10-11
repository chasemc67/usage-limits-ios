import Foundation
import SwiftUI

enum Fmt {
    /// "3d 4h", "2h 14m", "12m", "<1m".
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// "2d", "5h", "14m".
    static func compactCountdown(to date: Date, now: Date = Date()) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        if total >= 86_400 { return "\(total / 86_400)d" }
        if total >= 3600 { return "\(total / 3600)h" }
        return "\(max(1, total / 60))m"
    }

    static func resetsIn(_ date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        return interval <= 0 ? "reset due" : "resets in \(countdown(interval))"
    }

    /// Short local date + time in the user's timezone ("Today, 3:40 PM").
    static func absolute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "just now", "3m ago", "2h ago", "1d ago".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

enum UsageColor {
    static func color(for usedPercent: Double) -> Color {
        if usedPercent < 60 { return TMX.orange }
        if usedPercent < 85 { return TMX.amber }
        return TMX.red
    }
}
