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
                TerminalBox(title: "[ use it or lose it ]") {
                    ForEach(Array(nudges.enumerated()), id: \.element.id) { index, nudge in
                        if index > 0 {
                            DashedDivider(color: TMX.orange.opacity(0.3))
                                .padding(.vertical, 8)
                        }
                        UseItBanner(nudge: nudge, now: context.date) {
                            onSelect(nudge.kind)
                        } onDismiss: {
                            withAnimation(.snappy) { model.dismiss(nudge) }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct UseItBanner: View {
    let nudge: UseItNudge
    let now: Date
    let onSelect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onSelect) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TMX.amber)
                    Text(nudge.message(now: now))
                        .font(TMX.font(.subheadline))
                        .foregroundStyle(TMX.hi)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows \(nudge.kind.displayName)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TMX.dim)
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().strokeBorder(TMX.faint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss until reset")
        }
    }
}
