import SwiftUI
import AuthenticationServices

struct ServiceSettingsSheet: View {
    let kind: ServiceKind

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var webLoginFlow: WebLoginFlow?
    @State private var status: StatusMessage?
    @State private var busy = false

    // Manual entry fields
    @State private var cursorToken = ""
    @State private var codexAccessToken = ""
    @State private var codexAccountId = ""
    @State private var codexSessionCookie = ""
    @State private var claudeAccessToken = ""
    @State private var claudeRefreshToken = ""

    // Claude PKCE paste-back
    @State private var claudePKCE: ClaudeOAuth.PKCE?
    @State private var claudePastedCode = ""

    private var signedIn: Bool { model.isSignedIn(kind) }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                signInSection
                if kind == .claude {
                    claudePasteCodeSection
                }
                manualSection
                if signedIn {
                    Section {
                        Button("Sign Out", role: .destructive) {
                            model.signOut(kind)
                            status = StatusMessage(text: "Signed out", isError: false)
                        }
                        .foregroundStyle(TMX.red)
                    } footer: {
                        if kind.credentialGroup.count > 1 {
                            Text("Signs out of both Cursor and Grok Bot, and clears saved web cookies.")
                        } else {
                            Text("Removes the stored credentials from the Keychain and clears saved web cookies.")
                        }
                    }
                    .terminalSection()
                }
            }
            .fontDesign(.monospaced)
            .scrollContentBackground(.hidden)
            .background(TerminalBackground().ignoresSafeArea())
            .navigationTitle(kind.displayName.lowercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TMX.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(TMX.font(.body, weight: .bold))
                            .foregroundStyle(TMX.orange)
                    }
                }
            }
            .disabled(busy)
            .overlay {
                if busy {
                    ProgressView()
                        .tint(TMX.orange)
                        .padding(20)
                        .background(TMX.panel)
                        .overlay(Rectangle().strokeBorder(TMX.orange, lineWidth: 1))
                }
            }
            .fullScreenCover(item: $webLoginFlow) { flow in
                WebLoginScreen(flow: flow) { result in
                    handle(result)
                }
                .preferredColorScheme(.dark)
                .tint(TMX.orange)
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                ProviderLogo(kind: kind, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName.uppercased())
                        .font(TMX.font(.headline, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(TMX.hi)
                    Label(signedIn ? "signed in" : "not signed in",
                          systemImage: signedIn ? "checkmark.seal.fill" : "xmark.seal")
                        .font(TMX.font(.subheadline))
                        .foregroundStyle(signedIn ? TMX.green : TMX.dim)
                }
            }
            if let status {
                Text(status.text)
                    .font(TMX.font(.footnote))
                    .foregroundStyle(status.isError ? TMX.red : TMX.green)
            }
        } footer: {
            if kind.credentialGroup.count > 1 {
                Text("Cursor and Grok Bot share one Cursor login.")
            }
        }
        .terminalSection()
    }

    @ViewBuilder
    private var signInSection: some View {
        Section {
            switch kind {
            case .cursor, .grokBot:
                Button {
                    webLoginFlow = .cursor
                } label: {
                    Label("Sign in with Cursor", systemImage: "safari")
                }
            case .codex:
                Button {
                    webLoginFlow = .codex
                } label: {
                    Label("Sign in with ChatGPT", systemImage: "safari")
                }
            case .claude:
                Button {
                    let pkce = ClaudeOAuth.PKCE.generate()
                    claudePKCE = pkce
                    webLoginFlow = .claude(pkce)
                } label: {
                    Label("Sign in with Claude (in-app)", systemImage: "safari")
                }
                Button {
                    startClaudeBrowserLogin()
                } label: {
                    Label("Sign in via system browser, then paste code", systemImage: "arrow.up.forward.app")
                }
            }
        } header: {
            Text("Sign in")
        } footer: {
            switch kind {
            case .cursor, .grokBot:
                Text("Opens cursor.com in a web view and captures the WorkosCursorSessionToken cookie.")
            case .codex:
                Text("Opens chatgpt.com in a web view, then reads an access token from /api/auth/session.")
            case .claude:
                Text("OAuth with PKCE. If automatic capture doesn't work, use the system browser: copy the code shown after approving, tap Cancel, and paste it below.")
            }
        }
        .terminalSection()
    }

    private var claudePasteCodeSection: some View {
        Section {
            TextField("code#state", text: $claudePastedCode, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(TMX.font(.footnote))
            HStack {
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first {
                        claudePastedCode = first
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                Spacer()
                Button("Exchange Code") {
                    exchangeClaudeCode()
                }
                .buttonStyle(.borderedProminent)
                .tint(TMX.orange)
                .foregroundStyle(TMX.bg)
                .disabled(claudePKCE == nil || claudePastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Paste authorization code")
        } footer: {
            if claudePKCE == nil {
                Text("Start a login above first — the code is tied to that login attempt.")
            } else {
                Text("Paste the code shown on the Anthropic callback page (format code#state).")
            }
        }
        .terminalSection()
    }

    @ViewBuilder
    private var manualSection: some View {
        Section {
            switch kind {
            case .cursor, .grokBot:
                SecureField("WorkosCursorSessionToken", text: $cursorToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Token") { saveCursorToken() }
                    .disabled(cursorToken.trimmingCharacters(in: .whitespaces).isEmpty)

            case .codex:
                SecureField("Access token", text: $codexAccessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Account ID (optional)", text: $codexAccountId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Session cookie (optional, enables refresh)", text: $codexSessionCookie)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Token") { saveCodexTokens() }
                    .disabled(codexAccessToken.trimmingCharacters(in: .whitespaces).isEmpty
                              && codexSessionCookie.trimmingCharacters(in: .whitespaces).isEmpty)

            case .claude:
                SecureField("Access token", text: $claudeAccessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Refresh token (optional)", text: $claudeRefreshToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Token") { saveClaudeTokens() }
                    .disabled(claudeAccessToken.trimmingCharacters(in: .whitespaces).isEmpty
                              && claudeRefreshToken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Paste token manually")
        } footer: {
            switch kind {
            case .cursor, .grokBot:
                Text("From cursor.com → DevTools → Application → Cookies → WorkosCursorSessionToken. A bare JWT also works.")
            case .codex:
                Text("accessToken from chatgpt.com/api/auth/session. The session cookie is __Secure-next-auth.session-token.")
            case .claude:
                Text("An OAuth access token (sk-ant-oat…). With a refresh token the app renews it automatically.")
            }
        }
        .terminalSection()
    }

    // MARK: - Actions

    private func handle(_ result: WebLoginResult) {
        switch result {
        case .cursorCookie(let value):
            guard let normalized = CursorAuth.normalizedCookieValue(value) else {
                status = StatusMessage(text: "Couldn't read the Cursor session cookie", isError: true)
                return
            }
            TokenStore.cursorSessionToken = normalized
            signedInSuccessfully()

        case .codex(let session, let cookieHeader):
            CodexAuth.store(session, cookieHeader: cookieHeader)
            signedInSuccessfully()

        case .claudeCode(let code, let state):
            guard let pkce = claudePKCE else {
                status = StatusMessage(text: "Login expired — try again", isError: true)
                return
            }
            exchange(code: code, state: state, pkce: pkce)
        }
    }

    private func startClaudeBrowserLogin() {
        let pkce = ClaudeOAuth.PKCE.generate()
        claudePKCE = pkce
        claudePastedCode = ""
        let url = ClaudeOAuth.authorizationURL(for: pkce)
        Task {
            do {
                // The redirect is an https page that shows the code, so this normally ends
                // with the user tapping Cancel after copying it.
                let callback = try await webAuthenticationSession.authenticate(
                    using: url, callbackURLScheme: "usagelimits")
                if let parsed = ClaudeOAuth.parseCallbackURL(callback) {
                    exchange(code: parsed.code, state: parsed.state, pkce: pkce)
                }
            } catch {
                status = StatusMessage(text: "Paste the code you copied below.", isError: false)
            }
        }
    }

    private func exchangeClaudeCode() {
        guard let pkce = claudePKCE else { return }
        guard let parsed = ClaudeOAuth.parsePastedCode(claudePastedCode) else {
            status = StatusMessage(text: "That doesn't look like an authorization code", isError: true)
            return
        }
        exchange(code: parsed.code, state: parsed.state, pkce: pkce)
    }

    private func exchange(code: String, state: String?, pkce: ClaudeOAuth.PKCE) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await ClaudeOAuth.exchange(code: code, state: state, pkce: pkce)
                claudePKCE = nil
                claudePastedCode = ""
                signedInSuccessfully()
            } catch {
                status = StatusMessage(text: ServiceError.message(for: error), isError: true)
            }
        }
    }

    private func saveCursorToken() {
        guard let normalized = CursorAuth.normalizedCookieValue(cursorToken),
              CursorAuth.jwt(from: normalized) != nil else {
            status = StatusMessage(text: "Expected \"<userId>%3A%3A<JWT>\" or a JWT", isError: true)
            return
        }
        TokenStore.cursorSessionToken = normalized
        cursorToken = ""
        signedInSuccessfully()
    }

    private func saveCodexTokens() {
        let token = codexAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountId = codexAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            TokenStore.codexAccessToken = token
            TokenStore.codexAccountId = accountId.isEmpty ? CodexAuth.accountId(fromJWT: token) : accountId
        } else if !accountId.isEmpty {
            TokenStore.codexAccountId = accountId
        }
        if let cookie = CodexAuth.normalizedCookieHeader(codexSessionCookie) {
            TokenStore.codexSessionCookie = cookie
        }
        codexAccessToken = ""
        codexAccountId = ""
        codexSessionCookie = ""
        signedInSuccessfully()
    }

    private func saveClaudeTokens() {
        let access = claudeAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refresh = claudeRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !access.isEmpty {
            TokenStore.claudeAccessToken = access
            TokenStore.claudeExpiresAt = nil
        }
        if !refresh.isEmpty {
            TokenStore.claudeRefreshToken = refresh
        }
        claudeAccessToken = ""
        claudeRefreshToken = ""

        if access.isEmpty && !refresh.isEmpty {
            // Only a refresh token: mint an access token now.
            busy = true
            Task {
                defer { busy = false }
                do {
                    try await ClaudeOAuth.refresh()
                    signedInSuccessfully()
                } catch {
                    status = StatusMessage(text: ServiceError.message(for: error), isError: true)
                }
            }
        } else {
            signedInSuccessfully()
        }
    }

    private func signedInSuccessfully() {
        status = StatusMessage(text: "Signed in — refreshing…", isError: false)
        model.didSignIn(kind)
    }
}

private extension View {
    /// Flat dark rows with hairline separators.
    func terminalSection() -> some View {
        self
            .listRowBackground(TMX.panel)
            .listRowSeparatorTint(TMX.faint)
            .listSectionSeparatorTint(TMX.faint)
    }
}

private struct StatusMessage: Equatable {
    var text: String
    var isError: Bool
}
