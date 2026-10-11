import SwiftUI

/// Stacked "use it or lose it" banners, most urgent first.
struct UseItBannerStack: View {
    @EnvironmentObject private var model: AppModel
    let onSelect: (ServiceKind) -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let nudges = UseItNudge
                .nudges(snapshots: model.snapshots, isSignedIn: { model.isSignedIn($0) }, now: context.date)
                .filter { !model.isDismissed($0) }
                .prefix(ResetAlertConfig.standard.maxVisibleAlerts)

            if !nudges.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(nudges)) { nudge in
                        UseItBanner(nudge: nudge, now: context.date) {
                            onSelect(nudge.kind)
                        } onDismiss: {
                            withAnimation(.snappy) { model.dismiss(nudge) }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }
}

private struct UseItBanner: View {
    let nudge: UseItNudge
    let now: Date
    let onSelect: () -> Void
    let onDismiss: () -> Void

    private let tint = Color.orange

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(nudge.message(now: now))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows \(nudge.kind.displayName)")

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss until reset")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(0.10))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }
}
