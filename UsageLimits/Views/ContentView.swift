import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TitleHeader()

                        StatusHeader()

                        UseItBannerStack { kind in
                            withAnimation(.snappy) {
                                proxy.scrollTo(kind, anchor: .top)
                            }
                        }

                        if !model.anySignedIn {
                            EmptyStateCard()
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            TerminalDivider()
                            ForEach(ServiceKind.allCases) { kind in
                                ServiceCard(kind: kind)
                                    .id(kind)
                            }
                        }

                        Text("Unofficial. Uses private endpoints that may change at any time. Tokens are stored only in this device's Keychain.")
                            .font(TMX.font(.caption2))
                            .foregroundStyle(TMX.dim)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .background(TerminalBackground().ignoresSafeArea())
            .refreshable {
                await model.refreshAll()
            }
            .navigationTitle("Token Maxx")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $model.sheetKind) { kind in
                ServiceSettingsSheet(kind: kind)
                    .environmentObject(model)
                    .preferredColorScheme(.dark)
                    .tint(TMX.orange)
            }
        }
        .task {
            await model.refreshAll()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshIfStale() }
            }
        }
    }
}

/// "❯ Token Maxx" title with the accounts menu and refresh button.
private struct TitleHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                Text("❯")
                    .foregroundStyle(TMX.orange)
                    .accessibilityHidden(true)
                Text("Token Maxx")
                    .foregroundStyle(TMX.hi)
            }
            .font(TMX.font(size: 28, weight: .bold))
            .tracking(-0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Menu {
                ForEach(ServiceKind.allCases) { kind in
                    Button {
                        model.sheetKind = kind
                    } label: {
                        Label(kind.displayName, systemImage: kind.iconSystemName)
                    }
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(TMX.orange)
                    .frame(width: 36, height: 36)
                    .overlay(Rectangle().strokeBorder(TMX.faint, lineWidth: 1))
            }
            .accessibilityLabel("Accounts")

            Button {
                Task { await model.refreshAll() }
            } label: {
                Group {
                    if model.isRefreshingAny {
                        ProgressView()
                            .tint(TMX.orange)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(model.anySignedIn ? TMX.orange : TMX.dim)
                    }
                }
                .frame(width: 36, height: 36)
                .overlay(Rectangle().strokeBorder(TMX.faint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshingAny || !model.anySignedIn)
            .accessibilityLabel("Refresh")
        }
        .padding(.top, 4)
    }
}

private struct StatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(TMX.dim)
                if let updated = model.lastUpdated {
                    Text("updated \(Fmt.relative(updated, now: context.date))")
                } else {
                    Text("not updated yet")
                }
                Spacer()
                if model.isRefreshingAny {
                    Text("refreshing…")
                        .foregroundStyle(TMX.orange)
                }
            }
            .font(TMX.font(.caption))
            .foregroundStyle(TMX.dim)
        }
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(TMX.orange)
            Text("Track your AI usage limits")
                .font(TMX.font(.headline, weight: .bold))
                .foregroundStyle(TMX.hi)
            Text("Sign in to Cursor, Codex or Claude below. Your credentials never leave this device.")
                .font(TMX.font(.subheadline))
                .foregroundStyle(TMX.dim)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(Rectangle().strokeBorder(TMX.faint, lineWidth: 1))
    }
}
