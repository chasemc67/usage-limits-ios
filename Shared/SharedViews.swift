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

/// Anchor for the asset catalog compiled with this source (app, widget, or tests).
private final class TMXBundleToken {}

extension Bundle {
    static var tmxResources: Bundle { Bundle(for: TMXBundleToken.self) }
}

/// Bare orange provider logo.
struct ProviderLogo: View {
    var kind: ServiceKind
    var size: CGFloat = 28

    var body: some View {
        Image(kind.logoAssetName, bundle: .tmxResources)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.7, height: size * 0.7)
            .foregroundStyle(TMX.orange)
            .frame(width: size, height: size)
    }
}
