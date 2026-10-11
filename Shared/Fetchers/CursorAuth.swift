import Foundation

/// Helpers for the shared Cursor / Grok Bot credential: the `WorkosCursorSessionToken`
/// cookie, formatted "<userId>%3A%3A<JWT>".
enum CursorAuth {
    static let cookieName = "WorkosCursorSessionToken"
    static let dashboardServiceBase = "https://api2.cursor.sh/aiserver.v1.DashboardService/"

    /// Normalises whatever the user pasted (full cookie header, "uid::jwt", or a bare JWT)
    /// into the URL-encoded cookie value.
    static func normalizedCookieValue(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: cookieName + "=") {
            value = String(value[range.upperBound...])
        }
        if let semicolon = value.firstIndex(of: ";") {
            value = String(value[..<semicolon])
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\t"))
        guard !value.isEmpty else { return nil }

        if value.range(of: "%3A%3A", options: .caseInsensitive) != nil {
            return value
        }
        if value.contains("::") {
            return value.replacingOccurrences(of: "::", with: "%3A%3A")
        }
        if JWT.looksLikeJWT(value), let userId = userId(fromJWT: value) {
            return "\(userId)%3A%3A\(value)"
        }
        return value
    }

    /// The Bearer JWT is everything after the URL-encoded "::" separator.
    static func jwt(from cookieValue: String) -> String? {
        if let range = cookieValue.range(of: "%3A%3A", options: .caseInsensitive) {
            let token = String(cookieValue[range.upperBound...])
            return token.isEmpty ? nil : token
        }
        if let range = cookieValue.range(of: "::") {
            let token = String(cookieValue[range.upperBound...])
            return token.isEmpty ? nil : token
        }
        return JWT.looksLikeJWT(cookieValue) ? cookieValue : nil
    }

    /// `sub` looks like "auth0|user_XXXX" (or "google-oauth2|user_XXXX"); the cookie uses the part after "|".
    static func userId(fromJWT token: String) -> String? {
        guard let sub = JWT.payload(token)?["sub"].nonEmptyString else { return nil }
        if let bar = sub.lastIndex(of: "|") {
            return String(sub[sub.index(after: bar)...])
        }
        return sub
    }

    static func dashboardRequest(_ method: String, jwt: String) -> URLRequest {
        HTTP.request(URL(string: dashboardServiceBase + method)!,
                     method: "POST",
                     headers: [
                         "Authorization": "Bearer \(jwt)",
                         "Connect-Protocol-Version": "1",
                     ],
                     jsonBody: [:])
    }
}
