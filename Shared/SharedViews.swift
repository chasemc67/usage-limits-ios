import SwiftUI

/// Segmented bar showing used percent, color-coded by severity.
struct UsageBar: View {
    var usedPercent: Double
    var height: CGFloat = 8

    var body: some View {
        SegmentedBar(fraction: usedPercent / 100,
                     height: height,
                     fill: UsageColor.color(for: usedPercent),
                     cellWidth: height >= 8 ? 4 : 3,
                     gap: height >= 8 ? 2 : 1.5)
            .accessibilityElement()
            .accessibilityLabel("\(Fmt.percent(usedPercent)) used")
    }
}

/// Bare orange service glyph.
struct ServiceIcon: View {
    var kind: ServiceKind
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: kind.iconSystemName)
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(TMX.orange)
            .frame(width: size, height: size)
    }
}
