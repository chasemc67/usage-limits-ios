import Foundation
import CryptoKit

struct ClaudeFetcher: ServiceFetcher {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let rateLimitedUntilKey = "claude.rateLimitedUntil"
    private static let rateLimitedLabelKey = "claude.rateLimitedLabel"

    func fetch() async -> ServiceSnapshot {
        guard TokenStore.signedIn(.claude) else {
            return .failure(.claude, ServiceError.notSignedIn)
        }

        // Don't hammer after a 429: honour the stored Retry-After.
        let defaults = AppGroup.defaults
        if let until = defaults.object(forKey: Self.rateLimitedUntilKey) as? Date, until > Date() {
            let label = defaults.string(forKey: Self.rateLimitedLabelKey) ?? Fmt.countdown(until.timeIntervalSinceNow)
            return .failure(.claude, ServiceError.rateLimited(label))
        }

        do {
            var token = try await ClaudeOAuth.validAccessToken()
            var result = try await requestUsage(token)
            if result.status == 401, TokenStore.claudeRefreshToken != nil {
                token = try await ClaudeOAuth.refresh()
                result = try await requestUsage(token)
            }
            if result.status == 401 || result.status == 403 {
                throw ServiceError.sessionExpired
            }
            if result.status == 429 {
                let retryAfter = result.header("Retry-After")
                let (until, label) = Self.retryDeadline(retryAfter)
                defaults.set(until, forKey: Self.rateLimitedUntilKey)
                defaults.set(label, forKey: Self.rateLimitedLabelKey)
                throw ServiceError.rateLimited(label)
            }
            guard result.isSuccess else { throw result.serviceError() }
            guard let json = result.json, json.object != nil else {
                throw ServiceError.invalidResponse("oauth/usage")
            }
            defaults.removeObject(forKey: Self.rateLimitedUntilKey)
            defaults.removeObject(forKey: Self.rateLimitedLabelKey)
            return Self.snapshot(from: json)
        } catch {
            return .failure(.claude, error)
        }
    }

    private func requestUsage(_ token: String) async throws -> HTTPResult {
        try await HTTP.send(HTTP.request(Self.usageURL, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "UsageLimits-iOS/1.0",
        ]))
    }

    /// Retry-After may be delta-seconds or an HTTP-date. Defaults to 5 minutes.
    static func retryDeadline(_ header: String?) -> (Date, String) {
        let now = Date()
        if let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty {
            if let seconds = Double(header) {
                return (now.addingTimeInterval(max(seconds, 30)), "\(Int(seconds))s")
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header) {
                return (max(date, now.addingTimeInterval(30)), header)
            }
            return (now.addingTimeInterval(300), header)
        }
        return (now.addingTimeInterval(300), "5m")
    }

    static func snapshot(from json: JSONValue) -> ServiceSnapshot {
        let buckets: [(key: String, label: String, seconds: Int)] = [
            ("five_hour", "5-hour", 18_000),
            ("seven_day", "Weekly (all models)", 604_800),
            ("seven_day_opus", "Weekly Opus", 604_800),
            ("seven_day_sonnet", "Weekly Sonnet", 604_800),
        ]

        var windows: [UsageWindow] = []
        for bucket in buckets {
            let value = json[bucket.key]
            guard value.object != nil else { continue }
            windows.append(UsageWindow(id: "claude.\(bucket.key)",
                                       label: bucket.label,
                                       usedPercent: value["utilization"].double ?? 0,
                                       resetsAt: value["resets_at"].date,
                                       windowSeconds: bucket.seconds))
        }

        var extras: [String] = []
        let extra = json["extra_usage"]
        if extra.object != nil {
            if extra["is_enabled"].bool == true {
                // Amounts are reported in cents.
                let used = extra["used_credits"].double ?? 0
                if let limit = extra["monthly_limit"].double, limit > 0 {
                    extras.append("Extra usage: \(Money.dollars(cents: used)) of \(Money.dollars(cents: limit))")
                } else {
                    extras.append("Extra usage: \(Money.dollars(cents: used)) spent")
                }
            } else {
                extras.append("Extra usage: off")
            }
        }

        return ServiceSnapshot(kind: .claude, windows: windows, extras: extras, fetchedAt: Date(),
                               error: windows.isEmpty ? "No usage buckets reported" : nil)
    }
}

/// Claude Code public-client OAuth (PKCE).
enum ClaudeOAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let scope = "org:create_api_key user:profile user:inference"

    struct PKCE: Sendable, Hashable {
        let verifier: String
        let challenge: String
        let state: String

        static func generate() -> PKCE {
            let verifier = randomURLSafe(bytes: 32)
            let digest = SHA256.hash(data: Data(verifier.utf8))
            let challenge = Data(digest).base64URLEncodedString()
            return PKCE(verifier: verifier, challenge: challenge, state: randomURLSafe(bytes: 32))
        }

        private static func randomURLSafe(bytes count: Int) -> String {
            var generator = SystemRandomNumberGenerator()
            let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            return Data(bytes).base64URLEncodedString()
        }
    }

    static func authorizationURL(for pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"), // makes the callback page display the code
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    /// Accepts "code#state", a bare code, or a full callback URL.
    static func parsePastedCode(_ raw: String) -> (code: String, state: String?)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.scheme != nil, let parsed = parseCallbackURL(url) {
            return parsed
        }
        let parts = text.split(separator: "#", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else { return nil }
        return (code, parts.count > 1 ? parts[1] : nil)
    }

    /// Extracts `code` / `state` from the redirect URL (…/oauth/code/callback?code=…&state=…).
    static func parseCallbackURL(_ url: URL) -> (code: String, state: String?)? {
        guard url.path.contains("/oauth/code/callback"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return nil
        }
        return (code, items.first(where: { $0.name == "state" })?.value)
    }

    static func exchange(code: String, state: String?, pkce: PKCE) async throws {
        if let state, state != pkce.state {
            throw ServiceError.custom("State mismatch — start the login again")
        }
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state ?? pkce.state,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ]
        let result = try await HTTP.send(HTTP.request(tokenURL, method: "POST", jsonBody: body))
        guard result.isSuccess, let json = result.json else { throw result.serviceError() }
        try storeTokens(json)
    }

    @discardableResult
    static func refresh() async throws -> String {
        guard let refreshToken = TokenStore.claudeRefreshToken else {
            throw ServiceError.sessionExpired
        }
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        let result = try await HTTP.send(HTTP.request(tokenURL, method: "POST", jsonBody: body))
        if result.status == 400 || result.status == 401 {
            throw ServiceError.sessionExpired
        }
        guard result.isSuccess, let json = result.json else { throw result.serviceError() }
        return try storeTokens(json)
    }

    /// Returns a usable access token, refreshing first when it's expired or about to be.
    static func validAccessToken() async throws -> String {
        let access = TokenStore.claudeAccessToken
        let hasRefresh = TokenStore.claudeRefreshToken != nil
        if hasRefresh {
            if access == nil {
                return try await refresh()
            }
            if let expiresAt = TokenStore.claudeExpiresAt, expiresAt < Date().addingTimeInterval(120) {
                return try await refresh()
            }
        }
        guard let access else { throw ServiceError.notSignedIn }
        return access
    }

    @discardableResult
    private static func storeTokens(_ json: JSONValue) throws -> String {
        guard let access = json["access_token"].nonEmptyString else {
            throw ServiceError.invalidResponse("missing access_token")
        }
        TokenStore.claudeAccessToken = access
        if let refresh = json["refresh_token"].nonEmptyString {
            TokenStore.claudeRefreshToken = refresh
        }
        if let expiresIn = json["expires_in"].double {
            TokenStore.claudeExpiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            TokenStore.claudeExpiresAt = nil
        }
        return access
    }
}
