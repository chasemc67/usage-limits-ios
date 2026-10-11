import SwiftUI

/// Horizontal capsule bar showing used percent, color-coded by severity.
struct UsageBar: View {
    var usedPercent: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(usedPercent / 100, 0), 1)
            let color = UsageColor.color(for: usedPercent)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.18))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(Fmt.percent(usedPercent)) used")
    }
}

/// Circular ring gauge with arbitrary center content.
struct RingGauge<Content: View>: View {
    var usedPercent: Double
    var lineWidth: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        let fraction = min(max(usedPercent / 100, 0), 1)
        let color = UsageColor.color(for: usedPercent)
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
        }
    }
}

/// Rounded-square SF Symbol badge tinted with the service's brand color.
struct ServiceIcon: View {
    var kind: ServiceKind
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: kind.iconSystemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.brandColor.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
