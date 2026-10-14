import Foundation
import SwiftUI

enum ServiceKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case cursor
    case grokBot
    case codex
    case claude
    /// Derived section for unified (X Subscription) accounts: Cursor + Grok Bot in one card.
    /// Never fetched or signed into itself; built from the Cursor snapshot (see UnifiedPlan).
    case xai

    /// Fetched services only, so fetch, sign-in and settings loops never touch `.xai`.
    /// Display order comes from `UnifiedPlan.sectionKinds`.
    static var allCases: [ServiceKind] { [.cursor, .grokBot, .codex, .claude] }

    var isDerived: Bool { self == .xai }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .grokBot: return "Grok Bot"
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .xai: return "xAI"
        }
    }

    /// Template image in Shared/ProviderLogos.xcassets.
    var logoAssetName: String {
        switch self {
        case .cursor: return "LogoCursor"
        case .grokBot: return "LogoGrok"
        case .codex: return "LogoOpenAI"
        case .claude: return "LogoClaude"
        case .xai: return "LogoXAI"
        }
    }

    var brandColor: Color {
        switch self {
        case .cursor: return Color(red: 0.36, green: 0.42, blue: 0.98)
        case .grokBot: return Color(red: 0.10, green: 0.68, blue: 0.82)
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .xai: return Color(red: 0.10, green: 0.68, blue: 0.82)
        }
    }

    /// Services that share one stored credential with this one (Cursor + Grok Bot).
    var credentialGroup: [ServiceKind] {
        switch self {
        case .cursor, .grokBot, .xai: return [.cursor, .grokBot]
        case .codex: return [.codex]
        case .claude: return [.claude]
        }
    }
}

struct UsageWindow: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var label: String
    /// 0...100 (may exceed 100 when over the limit).
    var usedPercent: Double
    var resetsAt: Date?
    var windowSeconds: Int?
    var detail: String?

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    init(id: String? = nil,
         label: String,
         usedPercent: Double,
         resetsAt: Date? = nil,
         windowSeconds: Int? = nil,
         detail: String? = nil) {
        self.id = id ?? label
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
        self.detail = detail
    }
}

struct ServiceSnapshot: Codable, Sendable, Hashable, Identifiable {
    var kind: ServiceKind
    var windows: [UsageWindow]
    var extras: [String]
    var fetchedAt: Date
    var error: String?
    /// Cursor (X Subscription): spend on third-party models at API rates this billing cycle.
    /// Optional with a default so snapshots cached by older builds still decode.
    var thirdPartyCents: Double? = nil
    /// Start of the window `thirdPartyCents` covers (billing cycle start, or the sand period start).
    var thirdPartySince: Date? = nil
    /// Cursor / Grok Bot: whether the account is unified (X Subscription). Optional for the same reason.
    var unified: Bool? = nil

    var id: ServiceKind { kind }

    var mostConstrained: UsageWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }

    static func failure(_ kind: ServiceKind, _ error: Error) -> ServiceSnapshot {
        ServiceSnapshot(kind: kind, windows: [], extras: [], fetchedAt: Date(),
                        error: ServiceError.message(for: error))
    }

    /// If this snapshot is a pure failure, keep the previous data but surface the new error.
    func merged(onto previous: ServiceSnapshot?) -> ServiceSnapshot {
        guard error != nil, windows.isEmpty, let previous, !previous.windows.isEmpty else {
            return self
        }
        var copy = previous
        copy.error = error
        return copy
    }
}

enum ServiceError: LocalizedError, Sendable {
    case notSignedIn
    case sessionExpired
    case rateLimited(String)
    case http(Int, String?)
    case invalidResponse(String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in"
        case .sessionExpired:
            return "Session expired — sign in again"
        case .rateLimited(let retryAfter):
            return "Rate limited, retry after \(retryAfter)"
        case .http(let status, let body):
            if let body, !body.isEmpty { return "HTTP \(status): \(body)" }
            return "HTTP \(status)"
        case .invalidResponse(let what):
            return "Unexpected response: \(what)"
        case .custom(let text):
            return text
        }
    }

    static func message(for error: Error) -> String {
        if let serviceError = error as? ServiceError {
            return serviceError.errorDescription ?? "Unknown error"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "Offline"
            case .timedOut: return "Request timed out"
            case .cancelled: return "Cancelled"
            default: return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
