import SwiftUI

struct ServiceCard: View {
    let kind: ServiceKind
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let snapshot = model.snapshots[kind]
        let signedIn = model.isSignedIn(kind)

        VStack(alignment: .leading, spacing: 14) {
            header(snapshot: snapshot, signedIn: signedIn)

            if !signedIn {
                signedOutContent
            } else if let snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.windows) { window in
                    UsageWindowRow(window: window)
                }
                if !snapshot.extras.isEmpty {
                    extrasView(snapshot.extras)
                }
            } else if model.isRefreshing(kind) || snapshot == nil {
                loadingContent
            } else if let snapshot, !snapshot.extras.isEmpty {
                extrasView(snapshot.extras)
            }

            if signedIn, let error = snapshot?.error {
                errorRow(error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(kind.brandColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Pieces

    private func header(snapshot: ServiceSnapshot?, signedIn: Bool) -> some View {
        HStack(spacing: 12) {
            ServiceIcon(kind: kind, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.headline)
                if signedIn, let snapshot {
                    TimelineView(.everyMinute) { context in
                        Text("Updated \(Fmt.relative(snapshot.fetchedAt, now: context.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !signedIn {
                    Text("Not signed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isRefreshing(kind) {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                model.sheetKind = kind
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(kind.brandColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kind.displayName) settings")
        }
    }

    private var signedOutContent: some View {
        HStack {
            Text(signInBlurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Sign In") {
                model.sheetKind = kind
            }
            .buttonStyle(.borderedProminent)
            .tint(kind.brandColor)
        }
    }

    private var signInBlurb: String {
        switch kind {
        case .cursor, .grokBot: return "One Cursor login covers Cursor and Grok Bot."
        case .codex: return "Sign in with your ChatGPT account."
        case .claude: return "Sign in with your Claude account."
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Fetching usage…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }

    private func extrasView(_ extras: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(extras, id: \.self) { line in
                Label(line, systemImage: "info.circle")
                    .labelStyle(ExtraLabelStyle())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Retry") {
                Task { await model.refresh(kind.credentialGroup) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isRefreshing(kind))
        }
        .font(.caption)
        .foregroundStyle(.red)
    }
}

private struct ExtraLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

struct UsageWindowRow: View {
    let window: UsageWindow

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(window.label)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(Fmt.percent(window.usedPercent))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(UsageColor.color(for: window.usedPercent))
                }

                UsageBar(usedPercent: window.usedPercent, height: 8)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(Fmt.percent(window.remainingPercent)) left")
                    Spacer()
                    if let resetsAt = window.resetsAt {
                        Text(Fmt.resetsIn(resetsAt, now: context.date))
                            .monospacedDigit()
                            .fontDesign(.monospaced)
                        Text("· \(Fmt.absolute(resetsAt))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if let detail = window.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
