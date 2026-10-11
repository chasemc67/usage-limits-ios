import SwiftUI
import UIKit
import WebKit

enum WebLoginFlow: Identifiable {
    case cursor
    case codex
    case claude(ClaudeOAuth.PKCE)

    var id: String {
        switch self {
        case .cursor: return "cursor"
        case .codex: return "codex"
        case .claude(let pkce): return "claude-\(pkce.state)"
        }
    }

    var startURL: URL {
        switch self {
        case .cursor: return URL(string: "https://cursor.com/dashboard")!
        case .codex: return URL(string: "https://chatgpt.com/")!
        case .claude(let pkce): return ClaudeOAuth.authorizationURL(for: pkce)
        }
    }

    var title: String {
        switch self {
        case .cursor: return "Sign in to Cursor"
        case .codex: return "Sign in to ChatGPT"
        case .claude: return "Sign in to Claude"
        }
    }

    var hint: String {
        switch self {
        case .cursor: return "Log in normally — your session is captured automatically once the dashboard loads."
        case .codex: return "Log in to ChatGPT — the session is captured automatically once you're signed in."
        case .claude: return "Log in and approve access — the authorization code is captured automatically."
        }
    }
}

enum WebLoginResult {
    case cursorCookie(String)
    case codex(CodexAuth.Session, cookieHeader: String)
    case claudeCode(code: String, state: String?)
}

/// Full-screen wrapper with navigation chrome around the web view.
struct WebLoginScreen: View {
    let flow: WebLoginFlow
    let onComplete: (WebLoginResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebLoginView(flow: flow) { result in
                onComplete(result)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                Text(flow.hint)
                    .font(TMX.font(.footnote))
                    .foregroundStyle(TMX.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(TMX.panel)
                    .overlay(alignment: .bottom) { TerminalDivider() }
            }
            .background(TMX.bg.ignoresSafeArea())
            .navigationTitle(flow.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TMX.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(TMX.font(.body))
                            .foregroundStyle(TMX.orange)
                    }
                }
            }
        }
    }
}

struct WebLoginView: UIViewControllerRepresentable {
    let flow: WebLoginFlow
    let onComplete: (WebLoginResult) -> Void

    func makeUIViewController(context: Context) -> WebLoginViewController {
        WebLoginViewController(flow: flow, onComplete: onComplete)
    }

    func updateUIViewController(_ uiViewController: WebLoginViewController, context: Context) {}
}

final class WebLoginViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    private let flow: WebLoginFlow
    private let onComplete: (WebLoginResult) -> Void
    private var webView: WKWebView!
    private var finished = false
    private var codexSessionFetchInFlight = false

    init(flow: WebLoginFlow, onComplete: @escaping (WebLoginResult) -> Void) {
        self.flow = flow
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // A Safari UA keeps third-party sign-in providers happier inside a web view.
        webView.customUserAgent = HTTP.browserUserAgent
        view.addSubview(webView)

        configuration.websiteDataStore.httpCookieStore.add(self)
        webView.load(URLRequest(url: flow.startURL))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
    }

    // MARK: - Completion

    private func finish(_ result: WebLoginResult) {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        onComplete(result)
    }

    // MARK: - Cookie inspection

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        inspectCookies()
    }

    private func inspectCookies() {
        guard !finished else { return }
        switch flow {
        case .cursor, .codex:
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                self?.handle(cookies)
            }
        case .claude:
            break
        }
    }

    private func handle(_ cookies: [HTTPCookie]) {
        guard !finished else { return }
        switch flow {
        case .cursor:
            if let cookie = cookies.first(where: {
                $0.name == CursorAuth.cookieName && $0.domain.contains("cursor") && !$0.value.isEmpty
            }) {
                finish(.cursorCookie(cookie.value))
            }

        case .codex:
            let sessionCookies = cookies.filter {
                $0.name.hasPrefix(CodexAuth.sessionCookiePrefix) && $0.domain.contains("chatgpt.com")
            }
            guard !sessionCookies.isEmpty,
                  !codexSessionFetchInFlight,
                  let host = webView.url?.host, host.hasSuffix("chatgpt.com") else { return }
            fetchCodexSession(cookieHeader: CodexAuth.cookieHeader(from: sessionCookies))

        case .claude:
            break
        }
    }

    /// Calls /api/auth/session from inside the page so it carries the browser's cookies
    /// and passes any bot checks the page already cleared.
    private func fetchCodexSession(cookieHeader: String) {
        codexSessionFetchInFlight = true
        let script = """
        const response = await fetch('/api/auth/session', { credentials: 'include' });
        return await response.text();
        """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            self.codexSessionFetchInFlight = false
            guard case .success(let value) = result,
                  let text = value as? String,
                  let json = try? JSONValue.parse(Data(text.utf8)),
                  let session = CodexAuth.parseSession(json) else {
                return // Not logged in yet; we'll retry on the next cookie change / page load.
            }
            self.finish(.codex(session, cookieHeader: cookieHeader))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if case .claude = flow, let url = navigationAction.request.url,
           let callback = ClaudeOAuth.parseCallbackURL(url) {
            finish(.claudeCode(code: callback.code, state: callback.state))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if case .claude = flow, let url = webView.url, let callback = ClaudeOAuth.parseCallbackURL(url) {
            finish(.claudeCode(code: callback.code, state: callback.state))
            return
        }
        inspectCookies()
    }

    // MARK: - WKUIDelegate

    /// Sign-in providers often open popups; load them in the same web view instead.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// Clears persisted web sessions for a service on sign-out.
@MainActor
enum WebSessionCleaner {
    static func clear(for kind: ServiceKind) {
        let domains: [String]
        switch kind {
        case .cursor, .grokBot: domains = ["cursor.com", "cursor.sh", "workos"]
        case .codex: domains = ["chatgpt.com", "openai.com"]
        case .claude: domains = ["claude.ai", "anthropic.com"]
        }
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { record in
                domains.contains { record.displayName.contains($0) }
            }
            guard !matching.isEmpty else { return }
            store.removeData(ofTypes: types, for: matching) {}
        }
    }
}
