import Foundation

/// "The X Subscription" (Oct 2026): unified accounts where Grok, Grok Bot and Cursor draw
/// from one shared weekly pool (Grok-model usage only). Third-party models in Cursor are
/// billed at API list price from prepaid credit instead of an included pool.
/// Pure functions so detection and parsing can be unit-tested without the network.
enum UnifiedPlan {
    static let sharedWindowLabel = "Shared weekly"
    static let cursorSharedWindowID = "cursor.shared"

    /// Unified when any plan-name field names the X Subscription or contains "unified"
    /// (usage-summary reports `membershipType: "unified_ultra"` on live accounts, alongside
    /// a populated `individualUsage.plan` block, so plan pools must not veto this), or when
    /// GetSandUsageStatus succeeded and usage-summary reports no plan percentages.
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

    /// "unified_ultra", "Unified", "X Subscription", "x_subscription", "THE_X_SUBSCRIPTION";
    /// not "Max subscription".
    static func isXSubscription(_ text: String?) -> Bool {
        guard let text = text?.lowercased() else { return false }
        if text.contains("unified") { return true }
        return text.range(of: #"(^|[^a-z0-9])x[ _-]subscription"#, options: .regularExpression) != nil
    }

    /// Display name for a plan id: "unified_ultra" → "Ultra", "pro" → "Pro",
    /// "x_subscription" → "X Subscription". Nil when nothing but "unified" is left.
    static func planDisplayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
            .filter { $0 != "unified" }
        guard !words.isEmpty else { return nil }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Plan line for a unified account: usage-summary's `membershipType`, else sand's `cursorPlanName`.
    static func planName(summary: JSONValue?, sand: JSONValue?) -> String? {
        planDisplayName(summary?["membershipType"].nonEmptyString)
            ?? planDisplayName(sand?["cursorPlanName"].nonEmptyString)
    }

    // MARK: - Cursor snapshot

    /// Cursor's snapshot on a unified account: the shared weekly pool mirrored from
    /// GetSandUsageStatus, the Plan line and 3P spend. The billing-cycle pools in
    /// `individualUsage.plan` and the on-demand lines don't apply and are never shown.
    static func cursorSnapshot(summary: JSONValue?, sand: JSONValue, thirdPartyCents: Double?,
                               thirdPartySince: Date?, fetchedAt: Date = Date()) -> ServiceSnapshot {
        let window = GrokBotFetcher.weeklyWindow(from: sand, id: cursorSharedWindowID, label: sharedWindowLabel)
        return ServiceSnapshot(kind: .cursor, windows: [window], extras: planExtras(summary: summary, sand: sand),
                               fetchedAt: fetchedAt, error: nil, thirdPartyCents: thirdPartyCents,
                               thirdPartySince: thirdPartySince, unified: true)
    }

    static func planExtras(summary: JSONValue?, sand: JSONValue?) -> [String] {
        planName(summary: summary, sand: sand).map { ["Plan: \($0)"] } ?? []
    }

    // MARK: - Third-party spend

    // Where third-party spend comes from, and why only there:
    // * On unified accounts `individualUsage.plan` in usage-summary still carries a dollar pool
    //   (live: `used` 0 of `limit` 55395 cents, `apiPercentUsed` 0). That is the plan's
    //   included/prepaid credit, not a record of third-party spend, so it is never shown as 3P
    //   spend; nor is `individualUsage.onDemand`, which covers on-demand billing generally.
    // * The only clearly-labelled per-model spend is get-aggregated-usage-events: `totalCents`
    //   per `modelIntent`, summed over models that aren't Cursor's or xAI's own.
    // * A successful response with no third-party models is real data and shows $0.00. A failed
    //   request or one without `aggregations` shows nothing rather than a guess.

    /// First-party model ids, matched on the name after any "vendor/" prefix: grok*, composer*,
    /// cursor / cursor-*, and the exact pseudo-models "auto" and "default". Whole-name and
    /// prefix matches only, so third-party names that merely contain "auto" etc. still count.
    static func isFirstPartyModel(_ name: String) -> Bool {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespaces)
        let model = lowered.split(separator: "/").last.map(String.init) ?? lowered
        if ["auto", "default", "cursor"].contains(model) { return true }
        return ["grok", "composer", "cursor-"].contains { model.hasPrefix($0) }
    }

    /// Sum of `totalCents` (number or int64 string) over non-first-party models in a
    /// get-aggregated-usage-events response, or nil when the response has no `aggregations` array.
    static func thirdPartyCents(fromAggregatedUsage json: JSONValue) -> Double? {
        guard let aggregations = json["aggregations"].array else { return nil }
        return aggregations.reduce(0) { sum, item in
            guard let model = (item["modelIntent"].nonEmptyString ?? item["model"].nonEmptyString),
                  !isFirstPartyModel(model),
                  let cents = item["totalCents"].double, cents.isFinite else { return sum }
            return sum + cents
        }
    }

    /// Start of the 3P spend window: the billing cycle start, else one month before the cycle
    /// end, else the sand period start. Nil when none is known or it isn't before `now`.
    static func thirdPartyWindowStart(summary: JSONValue?, sand: JSONValue?, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let cycleStart = summary?["billingCycleStart"].date
            ?? summary?["billingCycleEnd"].date.flatMap { calendar.date(byAdding: .month, value: -1, to: $0) }
        guard let start = cycleStart ?? sand?["currentPeriodStart"].date, start < now else { return nil }
        return start
    }

    /// get-aggregated-usage-events request body: int64 ms-epoch strings, as cursor.com sends them.
    static func aggregatedUsageBody(start: Date, end: Date) -> [String: Any] {
        [
            "teamId": -1,
            "startDate": String(Int64(start.timeIntervalSince1970 * 1000)),
            "endDate": String(Int64(end.timeIntervalSince1970 * 1000)),
        ]
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
            // Cursor's Plan line ("Ultra") when it has one; Grok Bot's otherwise.
            if let cursorExtras = cursor?.extras, !cursorExtras.isEmpty {
                result.extras = cursorExtras
            } else {
                result.extras = grok.extras.filter { !$0.hasPrefix("Cursor plan:") }
            }
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
