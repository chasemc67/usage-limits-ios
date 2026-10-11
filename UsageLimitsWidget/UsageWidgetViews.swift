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
    var message = "Open Token Maxx to sign in"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(compact ? .title3 : .title)
                .foregroundStyle(TMX.orange)
                .widgetAccentable()
            Text(message)
                .font(TMX.font(.caption))
                .foregroundStyle(TMX.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared pieces (Home Screen)

extension TMX {
    /// Unlit bar segment.
    static let cellOff = Color(tmxHex: 0x2E2E2B)
    /// Provider header rule (slightly brighter than `faint`).
    static let groupRule = Color(tmxHex: 0x3A3A36)
}

private extension UsageWindow {
    /// Lowercased label without a trailing parenthetical: "Cursor Models (Auto)" -> "cursor models".
    var shortLabel: String {
        let full = label.lowercased()
        guard full.hasSuffix(")"), let open = full.range(of: " (") else { return full }
        return String(full[..<open.lowerBound])
    }
}

/// Bar with a fixed number of segments. The last lit segment fills in ⅛ steps,
/// so 1% shows a sliver and never looks the same as 4%.
private struct PartialSegmentBar: View {
    var usedPercent: Double
    var segments: Int
    var height: CGFloat = 9
    var gap: CGFloat = 1

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let trackColor = renderingMode == .fullColor ? TMX.cellOff : Color.primary.opacity(0.22)
        ZStack {
            SegmentShape(segments: segments, gap: gap, units: nil)
                .fill(trackColor)
            SegmentShape(segments: segments, gap: gap, units: Self.litUnits(usedPercent, segments: segments))
                .fill(UsageColor.color(for: usedPercent))
                .widgetAccentable()
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(Fmt.percent(usedPercent)) used")
    }

    /// Lit segments, with the fractional part rounded to eighths (at least ⅛ when anything is used).
    static func litUnits(_ usedPercent: Double, segments: Int) -> Double {
        let exact = min(max(usedPercent, 0), 100) / 100 * Double(segments)
        guard exact > 0 else { return 0 }
        let whole = exact.rounded(.down)
        let eighths = max(((exact - whole) * 8).rounded(), whole == 0 ? 1 : 0)
        return whole + eighths / 8
    }
}

/// All segments (`units == nil`) or the lit portion of a `PartialSegmentBar`.
private struct SegmentShape: Shape {
    var segments: Int
    var gap: CGFloat
    var units: Double?

    func path(in rect: CGRect) -> Path {
        let count = max(1, segments)
        let width = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        var path = Path()
        guard width > 0 else { return path }
        for index in 0..<count {
            let fill = units.map { min(max($0 - Double(index), 0), 1) } ?? 1
            guard fill > 0 else { break }
            path.addRect(CGRect(x: rect.minX + CGFloat(index) * (width + gap), y: rect.minY,
                                width: width * CGFloat(fill), height: rect.height))
        }
        return path
    }
}

/// "❯ command" on the left, dim status on the right.
private struct WidgetHeader: View {
    let command: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("❯")
                    .foregroundStyle(TMX.orange)
                    .widgetAccentable()
                Text(command)
                    .foregroundStyle(TMX.hi)
                    .tracking(0.3)
            }
            .font(TMX.font(size: 9.5, weight: .bold))
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(TMX.font(size: 9.5))
                    .foregroundStyle(TMX.dim)
            }
        }
        .lineLimit(1)
    }
}

private func updatedText(_ date: Date?, now: Date) -> String? {
    date.map { "updated \(Fmt.relative($0, now: now))" }
}

/// Approximate advance width of `count` characters in the monospaced font.
private func monoWidth(_ count: Int, size: CGFloat) -> CGFloat {
    CGFloat(count) * size * 0.61
}

// MARK: - System Small (one provider, chosen in the widget configuration)

private struct SmallWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        let kind = entry.provider.kind
        if let snapshot = entry.snapshot(for: kind) {
            VStack(alignment: .leading, spacing: 0) {
                header(snapshot)
                switch snapshot.windows.count {
                case 1:
                    SmallSinglePool(window: snapshot.windows[0], kind: kind, now: entry.date)
                case 2:
                    ForEach(snapshot.windows) { window in
                        SmallStackedPool(window: window, kind: kind, now: entry.date)
                            .padding(.top, 7)
                    }
                default:
                    ForEach(snapshot.windows) { window in
                        SmallPoolRow(window: window, kind: kind, now: entry.date)
                            .padding(.top, snapshot.windows.count > 3 ? 4 : 7)
                    }
                }
                Spacer(minLength: 0)
                if let updated = updatedText(snapshot.fetchedAt, now: entry.date) {
                    Text(updated)
                        .font(TMX.font(size: 9))
                        .foregroundStyle(TMX.dim)
                        .lineLimit(1)
                }
            }
        } else {
            EmptyWidgetView(compact: true, message: "Open Token Maxx to sign in to \(kind.displayName)")
        }
    }

    @ViewBuilder
    private func header(_ snapshot: ServiceSnapshot) -> some View {
        let count = snapshot.windows.count
        HStack(spacing: 5) {
            Text("❯")
                .foregroundStyle(TMX.orange)
                .widgetAccentable()
            Text(snapshot.kind.displayName.lowercased())
                .fontWeight(.bold)
                .foregroundStyle(TMX.hi)
            if count > 1 {
                Text(verbatim: "\(count) pools · % used")
                    .foregroundStyle(TMX.dim)
            }
            Spacer(minLength: 0)
            if count == 1 {
                ProviderLogo(kind: snapshot.kind, size: 14)
                    .widgetAccentable()
            }
        }
        .font(TMX.font(size: 9.5))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// S-grok / S-codex: one pool, one big number.
private struct SmallSinglePool: View {
    let window: UsageWindow
    let kind: ServiceKind
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(window.label.lowercased()) · 1 pool")
                .font(TMX.font(size: 10.5, weight: .bold))
                .foregroundStyle(TMX.hi)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Group {
                    Text("\(Int(window.usedPercent.rounded()))")
                        .font(TMX.font(size: 44, weight: .bold))
                        .tracking(-2)
                    Text(verbatim: "%")
                        .font(TMX.font(size: 22, weight: .bold))
                }
                .foregroundStyle(UsageColor.color(for: window.usedPercent))
                .widgetAccentable()
                Text("used")
                    .font(TMX.font(size: 11, weight: .medium))
                    .foregroundStyle(TMX.fg)
                    .padding(.leading, 5)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 3)

            PartialSegmentBar(usedPercent: window.usedPercent, segments: 20, height: 9)
                .padding(.top, 7)

            if let resetsAt = window.resetsAt {
                (Text("resets in ").foregroundStyle(TMX.dim)
                 + Text(Fmt.compactCountdown(to: resetsAt, now: now))
                    .fontWeight(.bold)
                    .foregroundStyle(TMX.resetIsSoon(window, kind: kind, now: now) ? TMX.amber : TMX.fg))
                    .font(TMX.font(size: 10))
                    .lineLimit(1)
                    .padding(.top, 7)
            }
        }
    }
}

/// S-claude: two pools at equal weight, each with a number, bar and reset.
private struct SmallStackedPool: View {
    let window: UsageWindow
    let kind: ServiceKind
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(window.label.lowercased())
                    .font(TMX.font(size: 9.5))
                    .foregroundStyle(TMX.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Group {
                    Text("\(Int(window.usedPercent.rounded()))")
                        .font(TMX.font(size: 22, weight: .bold))
                        .tracking(-1)
                    Text(verbatim: "%")
                        .font(TMX.font(size: 13, weight: .bold))
                }
                .foregroundStyle(UsageColor.color(for: window.usedPercent))
                .widgetAccentable()
                Text("used")
                    .font(TMX.font(size: 9))
                    .foregroundStyle(TMX.dim)
                    .padding(.leading, 4)
                Spacer(minLength: 4)
                if let resetsAt = window.resetsAt {
                    Text("resets ")
                        .font(TMX.font(size: 9.5))
                        .foregroundStyle(TMX.dim)
                    Text(Fmt.compactCountdown(to: resetsAt, now: now))
                        .font(TMX.font(size: 13, weight: .bold))
                        .foregroundStyle(TMX.resetColor(window, kind: kind, now: now))
                }
            }
            .lineLimit(1)

            PartialSegmentBar(usedPercent: window.usedPercent, segments: 24, height: 7)
        }
    }
}

/// S-cursor: compact pool row (label · reset over bar · %).
private struct SmallPoolRow: View {
    let window: UsageWindow
    let kind: ServiceKind
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                labelLine(window.label.lowercased())
                labelLine(window.shortLabel)
            }
            HStack(spacing: 6) {
                PartialSegmentBar(usedPercent: window.usedPercent, segments: 20, height: 8)
                Text(Fmt.percent(window.usedPercent))
                    .font(TMX.font(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TMX.hi)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
    }

    private func labelLine(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(TMX.fg)
                .fixedSize()
            Spacer(minLength: 6)
            if let resetsAt = window.resetsAt {
                Text(Fmt.compactCountdown(to: resetsAt, now: now))
                    .foregroundStyle(TMX.resetColor(window, kind: kind, now: now))
                    .fixedSize()
            }
        }
        .font(TMX.font(size: 9.5))
        .lineLimit(1)
    }
}

// MARK: - System Medium (M2b: weighted columns)

private struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        if entry.available.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(command: "tmx grid · % used",
                             trailing: updatedText(entry.lastUpdated, now: entry.date))
                GeometryReader { proxy in
                    let gap: CGFloat = 5
                    // 195 : 132, as in the mockup.
                    let wide = ((proxy.size.width - gap) * 195 / 327).rounded()
                    HStack(spacing: gap) {
                        VStack(spacing: gap) {
                            MediumCell(entry: entry, kind: .claude, wide: true)
                            MediumCell(entry: entry, kind: .cursor, wide: true)
                        }
                        .frame(width: wide)
                        VStack(spacing: gap) {
                            MediumCell(entry: entry, kind: .codex, wide: false)
                            MediumCell(entry: entry, kind: .grokBot, wide: false)
                        }
                    }
                }
            }
        }
    }
}

private struct MediumCell: View {
    let entry: UsageEntry
    let kind: ServiceKind
    let wide: Bool

    var body: some View {
        let snapshot = entry.snapshot(for: kind)
        let windows = snapshot?.windows ?? []

        VStack(alignment: .leading, spacing: 0) {
            header(windows: windows)

            if windows.isEmpty {
                Text((entry.snapshots[kind]?.error ?? "not signed in").lowercased())
                    .font(TMX.font(size: 9))
                    .foregroundStyle(TMX.dim)
                    .lineLimit(2)
                    .padding(.top, 3)
            } else if windows.count == 1 && !wide {
                bigNumber(windows[0])
            } else if windows.count <= 2 {
                ForEach(windows) { window in
                    twoLinePool(window)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    oneLineRows(windows, short: false, scales: false)
                    oneLineRows(windows, short: true, scales: false)
                    oneLineRows(windows, short: true, scales: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(Rectangle().strokeBorder(TMX.faint, lineWidth: 1))
        .clipped()
    }

    @ViewBuilder
    private func header(windows: [UsageWindow]) -> some View {
        // Narrow single-pool cells carry their reset under the number, so the header is just the name.
        let count: String? = switch windows.count {
        case 0: nil
        case 1: wide ? "1 pool" : nil
        default: "\(windows.count) pools"
        }
        ViewThatFits(in: .horizontal) {
            headerLine(count: count)
            headerLine(count: nil)
        }
        .frame(height: 13)
    }

    private func headerLine(count: String?) -> some View {
        HStack(spacing: 5) {
            ProviderLogo(kind: kind, size: 12)
                .widgetAccentable()
            Text(kind.displayName.lowercased())
                .font(TMX.font(size: 9.5, weight: .bold))
                .foregroundStyle(TMX.hi)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if let count {
                Text(count)
                    .font(TMX.font(size: 9))
                    .foregroundStyle(TMX.dim)
                    .fixedSize()
            }
        }
        .lineLimit(1)
    }

    /// Narrow single-pool cell: big number beside label and reset, full-width bar.
    private func bigNumber(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                Text(Fmt.percent(window.usedPercent))
                    .font(TMX.font(size: 22, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(UsageColor.color(for: window.usedPercent))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.label.lowercased())
                        .foregroundStyle(TMX.fg)
                        .minimumScaleFactor(0.6)
                    if let resetsAt = window.resetsAt {
                        (Text("resets ").foregroundStyle(TMX.dim)
                         + Text(Fmt.compactCountdown(to: resetsAt, now: entry.date))
                            .fontWeight(.bold)
                            .foregroundStyle(TMX.resetIsSoon(window, kind: kind, now: entry.date) ? TMX.amber : TMX.fg))
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("used")
                            .foregroundStyle(TMX.dim)
                    }
                }
                .font(TMX.font(size: 9))
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            PartialSegmentBar(usedPercent: window.usedPercent, segments: 20, height: 6)
        }
    }

    /// "label · reset" over "bar · %".
    private func twoLinePool(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                twoLinePoolLabel(window, label: window.label.lowercased(), scales: false)
                twoLinePoolLabel(window, label: window.shortLabel, scales: false)
                twoLinePoolLabel(window, label: window.shortLabel, scales: true)
            }
            HStack(spacing: 5) {
                PartialSegmentBar(usedPercent: window.usedPercent, segments: wide ? 24 : 14, height: 6)
                Text(Fmt.percent(window.usedPercent))
                    .font(TMX.font(size: 9.5, weight: .bold))
                    .foregroundStyle(TMX.hi)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 22, alignment: .trailing)
            }
        }
        .padding(.top, 2)
    }

    private func twoLinePoolLabel(_ window: UsageWindow, label: String, scales: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(TMX.fg)
                .minimumScaleFactor(scales ? 0.6 : 1)
                .fixedSize(horizontal: !scales, vertical: false)
            Spacer(minLength: 4)
            if let resetsAt = window.resetsAt {
                Text(Fmt.compactCountdown(to: resetsAt, now: entry.date))
                    .foregroundStyle(TMX.resetColor(window, kind: kind, now: entry.date))
                    .fixedSize()
            }
        }
        .font(TMX.font(size: 9))
        .lineLimit(1)
    }

    /// One row per pool: label · bar · % · reset (narrow cells drop the bar).
    /// `scales` is the last resort: labels shrink instead of overflowing.
    private func oneLineRows(_ windows: [UsageWindow], short: Bool, scales: Bool) -> some View {
        let labels = windows.map { short ? $0.shortLabel : $0.label.lowercased() }
        let labelWidth = scales ? 0 : labels.map { monoWidth($0.count, size: 9) }.max() ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                HStack(spacing: 3) {
                    Text(labels[index])
                        .foregroundStyle(TMX.fg)
                        .minimumScaleFactor(scales ? 0.6 : 1)
                        .fixedSize(horizontal: !scales, vertical: false)
                        .frame(minWidth: labelWidth, alignment: .leading)
                        .layoutPriority(scales ? 1 : 0)
                    if wide {
                        PartialSegmentBar(usedPercent: window.usedPercent, segments: 16, height: 6)
                            .frame(minWidth: scales ? 0 : 16, idealWidth: 40, maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 3)
                    }
                    Text(Fmt.percent(window.usedPercent))
                        .fontWeight(.bold)
                        .foregroundStyle(TMX.hi)
                        .fixedSize()
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(window.resetsAt.map { Fmt.compactCountdown(to: $0, now: entry.date) } ?? "")
                        .foregroundStyle(TMX.resetColor(window, kind: kind, now: entry.date))
                        .fixedSize()
                        .frame(minWidth: 16, alignment: .trailing)
                }
                .font(TMX.font(size: 9))
                .lineLimit(1)
                .frame(height: windows.count > 3 ? 12 : 13)
                .padding(.top, 1)
            }
        }
    }
}

// MARK: - System Large (L2a: banner + grouped bars, header rules)

private struct LargeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        let services = entry.available
        if services.isEmpty {
            EmptyWidgetView()
        } else {
            let nudges = entry.nudges
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(command: "tmx status --by=provider",
                             trailing: updatedText(entry.lastUpdated, now: entry.date))
                if let nudge = nudges.first {
                    NudgeBanner(nudge: nudge, others: nudges.count - 1, now: entry.date)
                        .padding(.top, 14)
                }
                // Shed row height when many pools (or the banner) need the room.
                ViewThatFits(in: .vertical) {
                    table(services, nudges: nudges, rowHeight: 19)
                    table(services, nudges: nudges, rowHeight: 16)
                    table(services, nudges: nudges, rowHeight: 14)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func table(_ services: [ServiceSnapshot], nudges: [UseItNudge],
                       rowHeight: CGFloat) -> some View {
        LargeTable(entry: entry, services: services,
                   flagged: Set(nudges.map { "\($0.kind.rawValue).\($0.window.id)" }),
                   rowHeight: rowHeight)
    }
}

/// Use-it-or-lose-it banner. Reference only: it names the pool and the countdown, and the
/// flagged row below carries the bar and numbers, so nothing is shown twice.
private struct NudgeBanner: View {
    let nudge: UseItNudge
    /// Further qualifying pools, also flagged in the list.
    let others: Int
    let now: Date

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ProviderLogo(kind: nudge.kind, size: 14)
                        .widgetAccentable()
                    Text("\(nudge.kind.displayName.lowercased()) · \(nudge.window.label.lowercased())")
                        .font(TMX.font(size: 11, weight: .bold))
                        .foregroundStyle(TMX.hi)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if others > 0 {
                    Text("+\(others) more")
                        .font(TMX.font(size: 9.5))
                        .foregroundStyle(TMX.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("in")
                    .font(TMX.font(size: 10, weight: .medium))
                    .foregroundStyle(TMX.fg)
                Text(Fmt.compactCountdown(to: nudge.resetsAt, now: now))
                    .font(TMX.font(size: 30, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(TMX.amber)
                    .shadow(color: TMX.amber.opacity(0.3), radius: 7)
                    .widgetAccentable()
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [TMX.amber.opacity(0.08), TMX.amber.opacity(0.015), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(Rectangle().strokeBorder(TMX.amber, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Text("[ USE IT OR LOSE IT ]")
                .font(TMX.font(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(TMX.amber)
                .padding(.horizontal, 5)
                .background(renderingMode == .fullColor ? TMX.bg : .clear)
                .offset(x: 10, y: -6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Use it or lose it: \(nudge.message(now: now))")
    }
}

private struct LargeTable: View {
    let entry: UsageEntry
    let services: [ServiceSnapshot]
    /// FocusItem ids of pools with a use-it-or-lose-it nudge.
    let flagged: Set<String>
    let rowHeight: CGFloat

    private static let segments = 25
    private static let indent: CGFloat = 17
    private static let percentWidth: CGFloat = 30
    private static let resetWidth: CGFloat = 30
    private static let labelSize: CGFloat = 9.5

    var body: some View {
        // Monospaced, so the widest label sets a shared column; labels never truncate.
        let labelWidth: CGFloat = services.flatMap { snapshot in
            snapshot.windows.map { monoWidth($0.label.count, size: Self.labelSize) }
        }.max() ?? 0

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("LIMIT").frame(width: labelWidth, alignment: .leading)
                Text(verbatim: "% USED").frame(maxWidth: .infinity, alignment: .leading)
                Text("USED").frame(width: Self.percentWidth, alignment: .trailing)
                Text("RESET").frame(width: Self.resetWidth, alignment: .trailing)
            }
            .font(TMX.font(size: 9))
            .tracking(0.3)
            .foregroundStyle(TMX.dim)
            .lineLimit(1)
            .padding(.leading, Self.indent)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) { TerminalDivider() }
            .padding(.top, 9)

            ForEach(services) { snapshot in
                groupHeader(snapshot)
                    .padding(.top, 7)
                ForEach(snapshot.windows) { window in
                    row(window, kind: snapshot.kind, labelWidth: labelWidth,
                        flagged: flagged.contains("\(snapshot.kind.rawValue).\(window.id)"))
                }
            }
        }
    }

    private func groupHeader(_ snapshot: ServiceSnapshot) -> some View {
        let count = snapshot.windows.count
        return HStack(spacing: 6) {
            ProviderLogo(kind: snapshot.kind, size: 13)
                .widgetAccentable()
            Text(snapshot.kind.displayName.uppercased())
                .font(TMX.font(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(TMX.hi)
                .fixedSize()
            if snapshot.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(TMX.red)
            }
            Rectangle()
                .fill(TMX.groupRule)
                .frame(height: 1)
            Text(count == 1 ? "1 pool" : "\(count) pools")
                .font(TMX.font(size: 9))
                .foregroundStyle(count > 1 ? TMX.fg : TMX.dim)
                .fixedSize()
        }
        .frame(height: 14)
    }

    private func row(_ window: UsageWindow, kind: ServiceKind, labelWidth: CGFloat,
                     flagged: Bool) -> some View {
        HStack(spacing: 6) {
            Text(window.label.lowercased())
                .foregroundStyle(flagged ? TMX.hi : TMX.fg)
                .fixedSize()
                .frame(minWidth: labelWidth, alignment: .leading)

            PartialSegmentBar(usedPercent: window.usedPercent, segments: Self.segments, height: 9)
                .frame(maxWidth: .infinity)

            Text(Fmt.percent(window.usedPercent))
                .fontWeight(.bold)
                .foregroundStyle(TMX.hi)
                .fixedSize()
                .frame(minWidth: Self.percentWidth, alignment: .trailing)

            Text(window.resetsAt.map { Fmt.compactCountdown(to: $0, now: entry.date) } ?? "—")
                .foregroundStyle(TMX.resetColor(window, kind: kind, now: entry.date))
                .fixedSize()
                .frame(minWidth: Self.resetWidth, alignment: .trailing)
        }
        .font(TMX.font(size: Self.labelSize))
        .lineLimit(1)
        .padding(.leading, Self.indent)
        .frame(height: rowHeight)
        .background {
            if flagged {
                LinearGradient(stops: [.init(color: TMX.amber.opacity(0.12), location: 0),
                                       .init(color: .clear, location: 0.7)],
                               startPoint: .leading, endPoint: .trailing)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(TMX.amber).frame(width: 2)
                    }
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
                ProviderLogo(kind: item.kind, size: 14)
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
                    ProviderLogo(kind: item.kind, size: 18)
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
    UsageProviderWidget()
} timeline: {
    UsageEntry.sample(provider: .claude)
    UsageEntry.sample(provider: .cursor)
    UsageEntry.sample(provider: .grokBot)
    UsageEntry.sample(provider: .codex)
}

#Preview(as: .systemMedium) {
    UsageOverviewWidget()
} timeline: {
    UsageEntry.sample()
}

#Preview(as: .systemLarge) {
    UsageOverviewWidget()
} timeline: {
    UsageEntry.sample()
}
