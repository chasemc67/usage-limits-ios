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
                    TerminalBackground()
                default:
                    // Removed by the system on the Lock Screen.
                    TMX.bg
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

private struct EmptyWidgetView: View {
    var compact = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(compact ? .title3 : .title)
                .foregroundStyle(TMX.orange)
                .widgetAccentable()
            Text("Open Token Maxx to sign in")
                .font(TMX.font(.caption))
                .foregroundStyle(TMX.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Orange glyph + uppercase service name.
private struct ServiceTag: View {
    let kind: ServiceKind
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 5) {
            ServiceIcon(kind: kind, size: size + 3)
                .widgetAccentable()
            Text(kind.displayName.uppercased())
                .font(TMX.font(size: size, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(TMX.hi)
                .lineLimit(1)
        }
    }
}

// MARK: - System Small

private struct SmallWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if let item = entry.focus {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    ServiceTag(kind: item.kind, size: 10)
                    Spacer(minLength: 0)
                }

                Text(item.window.label.lowercased())
                    .font(TMX.font(size: 11))
                    .foregroundStyle(TMX.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                Text(Fmt.percent(item.window.usedPercent))
                    .font(TMX.font(size: 40, weight: .bold))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .foregroundStyle(UsageColor.color(for: item.window.usedPercent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()

                UsageBar(usedPercent: item.window.usedPercent, height: 8)

                if let resetsAt = item.window.resetsAt {
                    Text(Fmt.resetsIn(resetsAt, now: entry.date))
                        .font(TMX.font(size: 10))
                        .foregroundStyle(TMX.resetColor(item.window, kind: item.kind, now: entry.date))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        DashedDivider()
                            .padding(.vertical, 6)
                    }
                    WidgetWindowRow(item: item, now: entry.date)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text("❯")
                            .foregroundStyle(TMX.orange)
                            .widgetAccentable()
                        Text("Token Maxx")
                            .foregroundStyle(TMX.hi)
                    }
                    .font(TMX.font(size: 15, weight: .bold))
                    Spacer()
                    if let updated = entry.lastUpdated {
                        Text("updated \(Fmt.relative(updated, now: entry.date))")
                            .font(TMX.font(size: 10))
                            .foregroundStyle(TMX.dim)
                    }
                }

                TerminalDivider()

                ForEach(Array(services.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 {
                        DashedDivider()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ServiceTag(kind: snapshot.kind, size: 11)
                            if snapshot.error != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(TMX.red)
                            }
                            Spacer()
                        }
                        ForEach(snapshot.windows.prefix(3)) { window in
                            CompactWindowRow(window: window, kind: snapshot.kind, now: entry.date)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ServiceIcon(kind: item.kind, size: 13)
                    .widgetAccentable()
                Text(item.kind.displayName.uppercased())
                    .font(TMX.font(size: 11, weight: .bold))
                    .foregroundStyle(TMX.hi)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(item.window.label.lowercased())
                    .font(TMX.font(size: 11))
                    .foregroundStyle(TMX.dim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let resetsAt = item.window.resetsAt {
                    Text(Fmt.resetsIn(resetsAt, now: now))
                        .font(TMX.font(size: 10))
                        .foregroundStyle(TMX.resetColor(item.window, kind: item.kind, now: now))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            HStack(spacing: 8) {
                UsageBar(usedPercent: item.window.usedPercent, height: 7)
                Text(Fmt.percent(item.window.usedPercent))
                    .font(TMX.font(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(UsageColor.color(for: item.window.usedPercent))
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

private struct CompactWindowRow: View {
    let window: UsageWindow
    let kind: ServiceKind
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label.lowercased())
                .font(TMX.font(size: 10))
                .foregroundStyle(TMX.fg)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
                .padding(.leading, 19)
            UsageBar(usedPercent: window.usedPercent, height: 6)
            Text(Fmt.percent(window.usedPercent))
                .font(TMX.font(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(UsageColor.color(for: window.usedPercent))
                .frame(width: 34, alignment: .trailing)
            if let resetsAt = window.resetsAt {
                Text(Fmt.compactCountdown(to: resetsAt, now: now))
                    .font(TMX.font(size: 10))
                    .foregroundStyle(TMX.resetColor(window, kind: kind, now: now))
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
                    .font(.system(.body, design: .monospaced, weight: .bold))
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
                    Text("\(item.kind.displayName) · \(item.window.label.lowercased())")
                        .lineLimit(1)
                }
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .minimumScaleFactor(0.7)
                .widgetAccentable()

                Gauge(value: min(max(item.window.usedPercent, 0), 100), in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)

                HStack(spacing: 4) {
                    Text(Fmt.percent(item.window.usedPercent))
                        .fontWeight(.bold)
                        .monospacedDigit()
                    if let resetsAt = item.window.resetsAt {
                        Text("· \(Fmt.resetsIn(resetsAt, now: entry.date))")
                            .lineLimit(1)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .minimumScaleFactor(0.8)
            }
        } else {
            Text("Token Maxx: sign in")
                .font(.system(.caption, design: .monospaced))
        }
    }
}

private struct InlineAccessoryView: View {
    let entry: UsageEntry

    var body: some View {
        Group {
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
        .fontDesign(.monospaced)
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

#Preview(as: .systemLarge) {
    UsageLimitsWidget()
} timeline: {
    UsageEntry.sample(configuration: UsageConfigurationIntent())
}
