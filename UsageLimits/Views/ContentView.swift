import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusHeader()

                    if !model.anySignedIn {
                        EmptyStateCard()
                    }

                    ForEach(ServiceKind.allCases) { kind in
                        ServiceCard(kind: kind)
                    }

                    Text("Unofficial. Uses private endpoints that may change at any time. Tokens are stored only in this device's Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(BackgroundGradient().ignoresSafeArea())
            .refreshable {
                await model.refreshAll()
            }
            .navigationTitle("Usage Limits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                    }
                    .accessibilityLabel("Accounts")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        if model.isRefreshingAny {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshingAny || !model.anySignedIn)
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(item: $model.sheetKind) { kind in
                ServiceSettingsSheet(kind: kind)
                    .environmentObject(model)
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

private struct StatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                if let updated = model.lastUpdated {
                    Text("Updated \(Fmt.relative(updated, now: context.date))")
                } else {
                    Text("Not updated yet")
                }
                Spacer()
                if model.isRefreshingAny {
                    Text("Refreshing…")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .padding(.horizontal, 4)
        }
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Track your AI usage limits")
                .font(.headline)
            Text("Sign in to Cursor, Codex or Claude below. Your credentials never leave this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.07, green: 0.08, blue: 0.14), Color(red: 0.03, green: 0.03, blue: 0.06)]
                : [Color(red: 0.92, green: 0.94, blue: 1.0), Color(red: 0.97, green: 0.96, blue: 0.98)],
            startPoint: .top,
            endPoint: .bottom)
    }
}
