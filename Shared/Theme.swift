import SwiftUI
import WidgetKit

/// Terminal-style palette and fonts shared by the app and the widget.
enum TMX {
    static let bg = Color(tmxHex: 0x0B0B0C)
    static let panel = Color(tmxHex: 0x131314)
    static let track = Color(tmxHex: 0x1E1E20)
    static let faint = Color(tmxHex: 0x2A2A2C)
    static let orange = Color(tmxHex: 0xFF6B1A)
    static let amber = Color(tmxHex: 0xFFB020)
    static let red = Color(tmxHex: 0xFF453A)
    static let green = Color(tmxHex: 0x3DDC84)
    static let dim = Color(tmxHex: 0x7A7A80)
    static let fg = Color(tmxHex: 0xD9D9D4)
    static let hi = Color(tmxHex: 0xF4F4EF)

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Whether a window's reset falls inside its "use it or lose it" lead time (shown in amber).
    static func resetIsSoon(_ window: UsageWindow, kind: ServiceKind, now: Date,
                            config: ResetAlertConfig = .standard) -> Bool {
        guard let resetsAt = window.resetsAt,
              let lead = config.leadTime(for: ResetWindowKind.infer(window, service: kind, config: config))
        else { return false }
        let remaining = resetsAt.timeIntervalSince(now)
        return remaining > 0 && remaining <= lead
    }

    static func resetColor(_ window: UsageWindow, kind: ServiceKind, now: Date) -> Color {
        resetIsSoon(window, kind: kind, now: now) ? amber : dim
    }
}

extension Color {
    init(tmxHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Bar made of discrete cells; filled cells on top of a dark track.
struct SegmentedBar: View {
    var fraction: Double
    var height: CGFloat = 8
    var fill: Color = TMX.orange
    var cellWidth: CGFloat = 4
    var gap: CGFloat = 2

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let trackColor = renderingMode == .fullColor ? TMX.track : Color.primary.opacity(0.22)
        ZStack {
            BarCells(fraction: clamped, filled: false, cellWidth: cellWidth, gap: gap)
                .fill(trackColor)
            BarCells(fraction: clamped, filled: true, cellWidth: cellWidth, gap: gap)
                .fill(fill)
                .widgetAccentable()
        }
        .frame(height: height)
    }
}

/// Either the filled cells or the remaining track cells of a `SegmentedBar`.
private struct BarCells: Shape {
    var fraction: Double
    var filled: Bool
    var cellWidth: CGFloat
    var gap: CGFloat

    func path(in rect: CGRect) -> Path {
        let count = max(1, Int((rect.width + gap) / (cellWidth + gap)))
        let step = (rect.width + gap) / CGFloat(count)
        let width = step - gap
        var lit = Int((Double(count) * fraction).rounded())
        if fraction > 0 { lit = max(lit, 1) }
        let range = filled ? 0..<lit : lit..<count
        var path = Path()
        for index in range {
            path.addRect(CGRect(x: rect.minX + CGFloat(index) * step, y: rect.minY,
                                width: width, height: rect.height))
        }
        return path
    }
}

/// Thin dashed horizontal rule.
struct DashedDivider: View {
    var color: Color = TMX.faint

    var body: some View {
        HorizontalLine()
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }
}

/// Solid hairline rule.
struct TerminalDivider: View {
    var color: Color = TMX.faint

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Near-black background with faint CRT scanlines.
struct TerminalBackground: View {
    var body: some View {
        TMX.bg
            .overlay {
                Canvas { context, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                     with: .color(.white.opacity(0.022)))
                        y += 3
                    }
                }
            }
            .allowsHitTesting(false)
    }
}

/// Thin bordered box with a bracketed label sitting on the top border.
struct TerminalBox<Content: View>: View {
    var title: String
    var color: Color = TMX.orange
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [color.opacity(0.07), color.opacity(0.015), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(Rectangle().strokeBorder(color, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(TMX.font(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .background(TMX.bg)
                .offset(x: 10, y: -8)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
