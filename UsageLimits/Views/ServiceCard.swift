import SwiftUI

struct ServiceCard: View {
    let kind: ServiceKind
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let snapshot = model.snapshot(kind)
        let signedIn = model.isSignedIn(kind)

        VStack(alignment: .leading, spacing: 12) {
            header(snapshot: snapshot, signedIn: signedIn)

            if !signedIn {
                signedOutContent
            } else if let snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.windows) { window in
                    UsageWindowRow(window: window, kind: kind)
                }
                if !extraLines(snapshot).isEmpty {
                    extrasView(extraLines(snapshot))
                }
            } else if model.isRefreshing(kind) || snapshot == nil {
                loadingContent
            } else if let snapshot, !extraLines(snapshot).isEmpty {
                extrasView(extraLines(snapshot))
            }

            if signedIn, let error = snapshot?.error {
                errorRow(error)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            DashedDivider()
        }
    }

    // MARK: - Pieces

    private func header(snapshot: ServiceSnapshot?, signedIn: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderLogo(kind: kind, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName.uppercased())
                    .font(TMX.font(.headline, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(TMX.hi)
                if signedIn, let snapshot {
                    TimelineView(.everyMinute) { context in
                        Text("updated \(Fmt.relative(snapshot.fetchedAt, now: context.date))")
                            .font(TMX.font(.caption))
                            .foregroundStyle(TMX.dim)
                    }
                } else if !signedIn {
                    Text("not signed in")
                        .font(TMX.font(.caption))
                        .foregroundStyle(TMX.dim)
                }
            }
            Spacer()
            if model.isRefreshing(kind) {
                ProgressView()
                    .controlSize(.small)
                    .tint(TMX.orange)
            }
            Button {
                model.sheetKind = kind
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TMX.orange)
                    .frame(width: 32, height: 28)
                    .overlay(Rectangle().strokeBorder(TMX.faint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kind.displayName) settings")
        }
    }

    private var signedOutContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(signInBlurb)
                .font(TMX.font(.caption))
                .foregroundStyle(TMX.dim)
            Spacer()
            Button {
                model.sheetKind = kind
            } label: {
                Text("[ sign in ]")
                    .font(TMX.font(.subheadline, weight: .bold))
                    .foregroundStyle(TMX.bg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(TMX.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign In")
        }
    }

    private var signInBlurb: String {
        switch kind {
        case .cursor, .grokBot, .xai: return "One Cursor login covers Cursor and Grok Bot."
        case .codex: return "Sign in with your ChatGPT account."
        case .claude: return "Sign in with your Claude account."
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(TMX.orange)
            Text("fetching usage…")
                .font(TMX.font(.subheadline))
                .foregroundStyle(TMX.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }

    private func extraLines(_ snapshot: ServiceSnapshot) -> [String] {
        guard let cents = snapshot.thirdPartyCents else { return snapshot.extras }
        let since = snapshot.thirdPartySince.map { " since \(Fmt.monthDay($0))" } ?? ""
        return snapshot.extras + ["3P API spend: \(Money.dollars(cents: cents))\(since)"]
    }

    private func extrasView(_ extras: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(extras, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("+")
                        .foregroundStyle(TMX.orange)
                        .accessibilityHidden(true)
                    Text(line)
                        .foregroundStyle(TMX.fg)
                }
            }
        }
        .font(TMX.font(.caption))
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await model.refresh(kind.credentialGroup) }
            } label: {
                Text("[ retry ]")
                    .font(TMX.font(.caption, weight: .bold))
                    .foregroundStyle(TMX.orange)
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing(kind))
            .accessibilityLabel("Retry")
        }
        .font(TMX.font(.caption))
        .foregroundStyle(TMX.red)
    }
}

struct UsageWindowRow: View {
    let window: UsageWindow
    let kind: ServiceKind

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(window.label.lowercased())
                        .font(TMX.font(.subheadline))
                        .foregroundStyle(TMX.fg)
                    Spacer()
                    Text(Fmt.percent(window.usedPercent))
                        .font(TMX.font(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(UsageColor.color(for: window.usedPercent))
                }

                UsageBar(usedPercent: window.usedPercent, height: 10)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Fmt.percent(window.remainingPercent)) left")
                        .foregroundStyle(TMX.hi)
                    Spacer()
                    if let resetsAt = window.resetsAt {
                        Text(Fmt.resetsIn(resetsAt, now: context.date))
                            .monospacedDigit()
                            .foregroundStyle(TMX.resetColor(window, kind: kind, now: context.date))
                        Text("· \(Fmt.absolute(resetsAt))")
                            .foregroundStyle(TMX.dim)
                    }
                }
                .font(TMX.font(.caption))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if let detail = window.detail {
                    Text(detail)
                        .font(TMX.font(.caption2))
                        .foregroundStyle(TMX.dim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
