import SwiftUI
import WidgetKit

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium, .systemLarge:
                    WidgetBackground()
                default:
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        case .accessoryCircular:
            CircularAccessoryView(entry: entry)
        case .accessoryRectangular:
            RectangularAccessoryView(entry: entry)
        case .accessoryInline:
            InlineAccessoryView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

private struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.10, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.09)]
                : [Color.white, Color(red: 0.94, green: 0.95, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}

private struct EmptyWidgetView: View {
    var compact = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(compact ? .title3 : .title)
                .foregroundStyle(.secondary)
            Text("Open Token Maxx to sign in")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - System Small

private struct SmallWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let item = entry.focus {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ServiceIcon(kind: item.kind, size: 20)
                    Text(item.kind.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                RingGauge(usedPercent: item.window.usedPercent, lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text(Fmt.percent(item.window.usedPercent))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                        Text(item.window.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let resetsAt = item.window.resetsAt {
                    Text(Fmt.resetsIn(resetsAt, now: entry.date))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            EmptyWidgetView(compact: true)
        }
    }
}

// MARK: - System Medium

private struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        let items = entry.topItems(limit: 3)
        if items.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    WidgetWindowRow(item: item, now: entry.date, showService: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - System Large

private struct LargeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        let services = entry.available
        if services.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Token Maxx")
                        .font(.headline)
                    Spacer()
                    if let updated = entry.lastUpdated {
                        Text("Updated \(Fmt.relative(updated, now: entry.date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(services) { snapshot in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            ServiceIcon(kind: snapshot.kind, size: 16)
                            Text(snapshot.kind.displayName)
                                .font(.caption.weight(.semibold))
                            if snapshot.error != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                        }
                        ForEach(snapshot.windows.prefix(3)) { window in
                            CompactWindowRow(window: window, now: entry.date)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WidgetWindowRow: View {
    let item: FocusItem
    let now: Date
    let showService: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if showService {
                    ServiceIcon(kind: item.kind, size: 16)
                    Text("\(item.kind.displayName) · \(item.window.label)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text(item.window.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.percent(item.window.usedPercent))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: item.window.usedPercent))
            }
            UsageBar(usedPercent: item.window.usedPercent, height: 6)
            if let resetsAt = item.window.resetsAt {
                Text(Fmt.resetsIn(resetsAt, now: now))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct CompactWindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
            UsageBar(usedPercent: window.usedPercent, height: 5)
            Text(Fmt.percent(window.usedPercent))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(UsageColor.color(for: window.usedPercent))
                .frame(width: 34, alignment: .trailing)
            if let resetsAt = window.resetsAt {
                Text(Fmt.compactCountdown(to: resetsAt, now: now))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

// MARK: - Accessory (Lock Screen)

private struct CircularAccessoryView: View {
    let entry: UsageEntry

    var body: some View {
        if let item = entry.focus {
            Gauge(value: min(max(item.window.usedPercent, 0), 100), in: 0...100) {
                Image(systemName: item.kind.iconSystemName)
            } currentValueLabel: {
                Text("\(Int(item.window.usedPercent.rounded()))")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "gauge.with.dots.needle.33percent")
            }
        }
    }
}

private struct RectangularAccessoryView: View {
    let entry: UsageEntry

    var body: some View {
        if let item = entry.focus {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: item.kind.iconSystemName)
                    Text("\(item.kind.displayName) · \(item.window.label)")
                        .lineLimit(1)
                }
                .font(.headline)
                .widgetAccentable()

                Gauge(value: min(max(item.window.usedPercent, 0), 100), in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)

                HStack {
                    Text(Fmt.percent(item.window.usedPercent))
                        .monospacedDigit()
                    if let resetsAt = item.window.resetsAt {
                        Text("· \(Fmt.resetsIn(resetsAt, now: entry.date))")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }
        } else {
            Text("Token Maxx: sign in")
                .font(.caption)
        }
    }
}

private struct InlineAccessoryView: View {
    let entry: UsageEntry

    var body: some View {
        if let item = entry.focus {
            if let resetsAt = item.window.resetsAt {
                Text("\(item.kind.displayName) \(Fmt.percent(item.window.usedPercent)) · \(Fmt.compactCountdown(to: resetsAt, now: entry.date))")
            } else {
                Text("\(item.kind.displayName) \(Fmt.percent(item.window.usedPercent))")
            }
        } else {
            Text("Token Maxx")
        }
    }
}

#Preview(as: .systemSmall) {
    UsageLimitsWidget()
} timeline: {
    UsageEntry.sample(configuration: UsageConfigurationIntent())
}

#Preview(as: .systemMedium) {
    UsageLimitsWidget()
} timeline: {
    UsageEntry.sample(configuration: UsageConfigurationIntent())
}
