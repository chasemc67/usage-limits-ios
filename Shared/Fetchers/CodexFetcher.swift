import Foundation

struct CodexFetcher: ServiceFetcher {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    func fetch() async -> ServiceSnapshot {
        guard TokenStore.signedIn(.codex) else {
            return .failure(.codex, ServiceError.notSignedIn)
        }

        do {
            var token = TokenStore.codexAccessToken
            if token == nil {
                // Only a session cookie was stored: mint an access token first.
                token = try await CodexAuth.refreshAccessToken()
            }
            guard var accessToken = token else { throw ServiceError.notSignedIn }

            var result = try await requestUsage(accessToken)
            if result.status == 401, TokenStore.codexSessionCookie != nil {
                if let refreshed = try? await CodexAuth.refreshAccessToken() {
                    accessToken = refreshed
                    result = try await requestUsage(accessToken)
                }
            }
            if result.status == 401 {
                throw ServiceError.sessionExpired
            }
            guard result.isSuccess else { throw result.serviceError() }
            guard let json = result.json, json.object != nil else {
                throw ServiceError.invalidResponse("wham/usage")
            }
            return Self.snapshot(from: json)
        } catch {
            return .failure(.codex, error)
        }
    }

    private func requestUsage(_ token: String) async throws -> HTTPResult {
        var headers = [
            "Authorization": "Bearer \(token)",
            "User-Agent": HTTP.browserUserAgent,
            "Accept": "application/json",
        ]
        if let accountId = TokenStore.codexAccountId {
            headers["ChatGPT-Account-Id"] = accountId
        }
        return try await HTTP.send(HTTP.request(Self.usageURL, headers: headers))
    }

    static func snapshot(from json: JSONValue) -> ServiceSnapshot {
        let rateLimit = json["rate_limit"]
        var windows: [UsageWindow] = []

        for (key, fallbackLabel) in [("primary_window", "Primary"), ("secondary_window", "Secondary")] {
            let window = rateLimit[key]
            guard window.object != nil else { continue }

            let seconds = window["limit_window_seconds"].int
            var resetsAt = window["reset_at"].date
            if resetsAt == nil, let after = window["reset_after_seconds"].double {
                resetsAt = Date().addingTimeInterval(after)
            }
            windows.append(UsageWindow(id: "codex.\(key)",
                                       label: label(forWindowSeconds: seconds) ?? fallbackLabel,
                                       usedPercent: window["used_percent"].double ?? 0,
                                       resetsAt: resetsAt,
                                       windowSeconds: seconds))
        }

        var extras: [String] = []
        if let plan = json["plan_type"].nonEmptyString {
            extras.append("Plan: \(plan.capitalized)")
        }
        if rateLimit["limit_reached"].bool == true {
            extras.append("Limit reached")
        }
        let credits = json["credits"]
        if credits["has_credits"].bool == true {
            if credits["unlimited"].bool == true {
                extras.append("Credits: unlimited")
            } else if let balance = credits["balance"].nonEmptyString {
                extras.append("Credits: \(balance)")
            }
        }
        if let available = json["rate_limit_reset_credits"]["available_count"].int {
            extras.append("Reset credits available: \(available)")
        }

        return ServiceSnapshot(kind: .codex, windows: windows, extras: extras, fetchedAt: Date(),
                               error: windows.isEmpty ? "No rate-limit windows reported" : nil)
    }

    static func label(forWindowSeconds seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        switch seconds {
        case 18_000: return "5-hour"
        case 604_800: return "Weekly"
        default:
            if seconds % 3600 == 0 { return "\(seconds / 3600)-hour" }
            if seconds >= 3600 { return String(format: "%.1f-hour", Double(seconds) / 3600) }
            return "\(max(1, seconds / 60))-minute"
        }
    }
}

/// ChatGPT session handling: `/api/auth/session` mints a short-lived access token
/// from the long-lived next-auth session cookie.
enum CodexAuth {
    static let sessionURL = URL(string: "https://chatgpt.com/api/auth/session")!
    static let sessionCookiePrefix = "__Secure-next-auth.session-token"

    struct Session: Sendable {
        var accessToken: String
        var accountId: String?
    }

    static func parseSession(_ json: JSONValue) -> Session? {
        guard let token = json["accessToken"].nonEmptyString else { return nil }
        let accountId = json["account"]["id"].nonEmptyString
            ?? json["account_id"].nonEmptyString
            ?? accountId(fromJWT: token)
        return Session(accessToken: token, accountId: accountId)
    }

    static func accountId(fromJWT token: String) -> String? {
        JWT.payload(token)?["https://api.openai.com/auth"]["chatgpt_account_id"].nonEmptyString
    }

    /// Accepts a bare cookie value or a "name=value; name2=value2" fragment.
    static func normalizedCookieHeader(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("=") && trimmed.contains(sessionCookiePrefix) {
            return trimmed
        }
        return "\(sessionCookiePrefix)=\(trimmed)"
    }

    static func cookieHeader(from cookies: [HTTPCookie]) -> String {
        cookies
            .filter { $0.name.hasPrefix(sessionCookiePrefix) }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    static func store(_ session: Session, cookieHeader: String?) {
        TokenStore.codexAccessToken = session.accessToken
        if let accountId = session.accountId {
            TokenStore.codexAccountId = accountId
        }
        if let cookieHeader, !cookieHeader.isEmpty {
            TokenStore.codexSessionCookie = cookieHeader
        }
    }

    /// Re-calls /api/auth/session with the stored session cookie and stores the fresh token.
    static func refreshAccessToken() async throws -> String {
        guard let cookie = TokenStore.codexSessionCookie else {
            throw ServiceError.sessionExpired
        }
        let request = HTTP.request(sessionURL, headers: [
            "Cookie": cookie,
            "User-Agent": HTTP.browserUserAgent,
            "Referer": "https://chatgpt.com/",
        ])
        let result = try await HTTP.send(request)
        guard result.isSuccess, let json = result.json, let session = parseSession(json) else {
            throw ServiceError.sessionExpired
        }

        // next-auth may rotate the session cookie; keep the newest one.
        let rotated = HTTPCookie.cookies(withResponseHeaderFields: result.headers, for: sessionURL)
        let rotatedHeader = cookieHeader(from: rotated)
        store(session, cookieHeader: rotatedHeader.isEmpty ? nil : rotatedHeader)
        return session.accessToken
    }
}
