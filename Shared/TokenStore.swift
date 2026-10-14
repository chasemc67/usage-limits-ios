import Foundation

/// Keychain account names for each credential.
enum TokenKey {
    static let cursorSessionToken = "cursor.sessionToken"
    static let codexAccessToken = "codex.accessToken"
    static let codexAccountId = "codex.accountId"
    static let codexSessionCookie = "codex.sessionCookie"
    static let claudeAccessToken = "claude.accessToken"
    static let claudeRefreshToken = "claude.refreshToken"
    static let claudeExpiresAt = "claude.expiresAt"
}

/// Typed accessors over `KeychainStore`. Setting `nil` or an empty string deletes the item.
enum TokenStore {
    // MARK: Cursor / Grok Bot (shared login)

    /// The raw `WorkosCursorSessionToken` cookie value: "<userId>%3A%3A<JWT>".
    static var cursorSessionToken: String? {
        get { get(TokenKey.cursorSessionToken) }
        set { set(TokenKey.cursorSessionToken, newValue) }
    }

    // MARK: Codex

    static var codexAccessToken: String? {
        get { get(TokenKey.codexAccessToken) }
        set { set(TokenKey.codexAccessToken, newValue) }
    }

    static var codexAccountId: String? {
        get { get(TokenKey.codexAccountId) }
        set { set(TokenKey.codexAccountId, newValue) }
    }

    /// A Cookie header fragment, e.g. "__Secure-next-auth.session-token=…" (possibly chunked .0/.1).
    static var codexSessionCookie: String? {
        get { get(TokenKey.codexSessionCookie) }
        set { set(TokenKey.codexSessionCookie, newValue) }
    }

    // MARK: Claude

    static var claudeAccessToken: String? {
        get { get(TokenKey.claudeAccessToken) }
        set { set(TokenKey.claudeAccessToken, newValue) }
    }

    static var claudeRefreshToken: String? {
        get { get(TokenKey.claudeRefreshToken) }
        set { set(TokenKey.claudeRefreshToken, newValue) }
    }

    static var claudeExpiresAt: Date? {
        get {
            guard let raw = get(TokenKey.claudeExpiresAt), let seconds = Double(raw) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        set {
            set(TokenKey.claudeExpiresAt, newValue.map { String(Int($0.timeIntervalSince1970)) })
        }
    }

    // MARK: Status

    static func signedIn(_ kind: ServiceKind) -> Bool {
        switch kind {
        case .cursor, .grokBot, .xai:
            return cursorSessionToken != nil
        case .codex:
            return codexAccessToken != nil || codexSessionCookie != nil
        case .claude:
            return claudeAccessToken != nil || claudeRefreshToken != nil
        }
    }

    /// Clears every credential belonging to `kind`. Cursor and Grok Bot share one credential.
    static func signOut(_ kind: ServiceKind) {
        switch kind {
        case .cursor, .grokBot, .xai:
            cursorSessionToken = nil
        case .codex:
            codexAccessToken = nil
            codexAccountId = nil
            codexSessionCookie = nil
        case .claude:
            claudeAccessToken = nil
            claudeRefreshToken = nil
            claudeExpiresAt = nil
        }
    }

    // MARK: Private

    private static func get(_ key: String) -> String? {
        guard let value = KeychainStore.read(key), !value.isEmpty else { return nil }
        return value
    }

    private static func set(_ key: String, _ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            KeychainStore.delete(key)
        } else {
            KeychainStore.save(key, trimmed)
        }
    }
}
