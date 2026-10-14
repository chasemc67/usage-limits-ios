import Foundation

/// "The X Subscription" (Oct 2026): unified accounts where Grok, Grok Bot and Cursor draw
/// from one shared weekly pool (Grok-model usage only). Third-party models in Cursor are
/// billed at API list price from prepaid credit instead of an included pool.
/// Pure functions so detection and parsing can be unit-tested without the network.
enum UnifiedPlan {
    static let sharedWindowLabel = "Shared weekly"
    static let cursorSharedWindowID = "cursor.shared"

    /// Unified when GetSandUsageStatus succeeded and usage-summary reports no plan percentages,
    /// or when any plan-name field names the X Subscription.
    static func isUnified(summary: JSONValue?, sand: JSONValue?) -> Bool {
        if namesXSubscription(summary: summary, sand: sand) { return true }
        guard let sand, sand.object != nil, let summary, summary.object != nil else { return false }
        return !planHasPercentages(summary["individualUsage"]["plan"])
    }

    static func planHasPercentages(_ plan: JSONValue) -> Bool {
        ["autoPercentUsed", "apiPercentUsed", "totalPercentUsed", "limit"].contains { plan[$0].double != nil }
    }

    static func namesXSubscription(summary: JSONValue?, sand: JSONValue?) -> Bool {
        var candidates: [JSONValue] = []
        if let summary {
            candidates += [summary["membershipType"], summary["subscription"], summary["planName"]]
        }
        if let sand {
            candidates += [sand["cursorPlanName"], sand["grokPlanLabel"], sand["subscription"], sand["planName"]]
        }
        return candidates.contains { value in
            // `subscription` may be an object ({"name": ...}); check its direct string fields too.
            if let object = value.object {
                return object.values.contains { isXSubscription($0.string) }
            }
            return isXSubscription(value.string)
        }
    }

    /// "X Subscription", "x_subscription", "THE_X_SUBSCRIPTION"; not "Max subscription".
    static func isXSubscription(_ text: String?) -> Bool {
        guard let text = text?.lowercased() else { return false }
        return text.range(of: #"(^|[^a-z0-9])x[ _-]subscription"#, options: .regularExpression) != nil
    }

    // MARK: - Third-party spend

    static let firstPartyMarkers = ["grok", "composer", "auto", "default", "cursor"]

    static func isFirstPartyModel(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return firstPartyMarkers.contains { lowered.contains($0) }
    }

    /// Sum of `totalCents` over non-first-party models in a get-aggregated-usage-events
    /// response, or nil when the response has no `aggregations` array.
    static func thirdPartyCents(fromAggregatedUsage json: JSONValue) -> Double? {
        guard let aggregations = json["aggregations"].array else { return nil }
        return aggregations.reduce(0) { sum, item in
            guard let model = item["modelIntent"].nonEmptyString, !isFirstPartyModel(model),
                  let cents = item["totalCents"].double, cents.isFinite else { return sum }
            return sum + cents
        }
    }
}

// MARK: - xAI section

extension ServiceSnapshot {
    /// Snapshots cached before `unified` existed are unified if they carry the mirrored shared pool.
    var isUnified: Bool {
        unified ?? windows.contains { $0.id == UnifiedPlan.cursorSharedWindowID }
    }
}

extension UnifiedPlan {
    /// Cursor decides when it has data; otherwise Grok Bot's flag.
    static func isUnified(_ snapshots: [ServiceKind: ServiceSnapshot]) -> Bool {
        if let cursor = snapshots[.cursor], !cursor.windows.isEmpty { return cursor.isUnified }
        return snapshots[.grokBot]?.isUnified ?? false
    }

    /// Display order. On unified accounts xAI takes Cursor's place and Grok Bot is folded in.
    static func sectionKinds(_ snapshots: [ServiceKind: ServiceSnapshot]) -> [ServiceKind] {
        guard isUnified(snapshots) else { return ServiceKind.allCases }
        return ServiceKind.allCases.compactMap { kind -> ServiceKind? in
            switch kind {
            case .cursor: return .xai
            case .grokBot: return nil
            default: return kind
            }
        }
    }

    /// The section showing `kind`: Cursor / Grok Bot map to xAI when unified, xAI to Cursor otherwise.
    static func section(for kind: ServiceKind, in snapshots: [ServiceKind: ServiceSnapshot]) -> ServiceKind {
        switch kind {
        case .cursor, .grokBot: return isUnified(snapshots) ? .xai : kind
        case .xai: return isUnified(snapshots) ? .xai : .cursor
        default: return kind
        }
    }

    /// A section's snapshot; xAI is derived, everything else is stored as fetched.
    static func sectionSnapshot(_ kind: ServiceKind,
                                in snapshots: [ServiceKind: ServiceSnapshot]) -> ServiceSnapshot? {
        kind == .xai ? xaiSnapshot(snapshots) : snapshots[kind]
    }

    /// Cursor's unified snapshot (shared weekly pool, Plan, 3P spend) relabelled as xAI.
    /// Falls back to Grok Bot's copy of the pool when Cursor has no data.
    static func xaiSnapshot(_ snapshots: [ServiceKind: ServiceSnapshot]) -> ServiceSnapshot? {
        guard isUnified(snapshots) else { return nil }
        let cursor = snapshots[.cursor]
        var result: ServiceSnapshot
        if let cursor, !cursor.windows.isEmpty {
            result = cursor
        } else if let grok = snapshots[.grokBot] {
            result = grok
            result.extras = grok.extras.filter { !$0.hasPrefix("Cursor plan:") }
            result.thirdPartyCents = cursor?.thirdPartyCents
            result.thirdPartySince = cursor?.thirdPartySince
            result.error = cursor?.error ?? grok.error
        } else if let cursor {
            result = cursor
        } else {
            return nil
        }
        result.kind = .xai
        result.unified = true
        return result
    }
}
