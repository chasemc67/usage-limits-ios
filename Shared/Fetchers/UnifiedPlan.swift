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

    // Third-party models on unified accounts are billed at API list price, and grok.com's
    // Billing page ("Monthly additional usage") is the true record of that. It lives on
    // grok.com/dashboard/billing behind separate grok.com auth that the Cursor cookie can't
    // reach, so it isn't used; the line is derived from Cursor's usage events instead.
    // * Only billed usage counts. Cursor's per-event `kind` separates usage covered by the plan
    //   (USAGE_EVENT_KIND_INCLUDED_IN_PRO / ..._INCLUDED_IN_BUSINESS / ...) from usage billed on
    //   top (USAGE_EVENT_KIND_USAGE_BASED), and `chargedCents` is what was actually charged.
    //   `tokenUsage.totalCents` is the API-price cost of the tokens whether billed or not (one
    //   live account showed $319.27 of it against $0.00 of additional usage), so on its own it
    //   is never treated as spend.
    // * get-filtered-usage-events is preferred: it carries `kind` / `chargedCents` per event.
    //   get-aggregated-usage-events is a fallback only when its items carry an explicit billed
    //   field; with only `totalCents` the line is hidden (nil) rather than overstated.
    // * `individualUsage.plan` (live: `used` 0 of `limit` 55395 cents) is the plan's included
    //   credit and `individualUsage.onDemand` covers on-demand billing generally; neither is a
    //   record of third-party spend, so neither is shown as such.
    // * A successful response with no billed third-party events is real data and shows $0.00.

    static let usageEventsPageSize = 500
    /// Cap on get-filtered-usage-events pages per refresh (5,000 events); beyond it the total
    /// covers only the most recent events.
    static let usageEventsMaxPages = 10

    /// First-party model ids, matched on the name after any "vendor/" prefix: grok*, composer*,
    /// cursor / cursor-*, and the exact pseudo-models "auto" and "default". Whole-name and
    /// prefix matches only, so third-party names that merely contain "auto" etc. still count.
    static func isFirstPartyModel(_ name: String) -> Bool {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespaces)
        let model = lowered.split(separator: "/").last.map(String.init) ?? lowered
        if ["auto", "default", "cursor"].contains(model) { return true }
        return ["grok", "composer", "cursor-"].contains { model.hasPrefix($0) }
    }

    /// The events on one get-filtered-usage-events page. An empty page may omit the array
    /// (proto3 JSON drops empty repeated fields), so `{}` or a zero count is an empty page;
    /// anything else without `usageEventsDisplay` is nil.
    static func usageEvents(fromFilteredUsage json: JSONValue) -> [JSONValue]? {
        if let events = json["usageEventsDisplay"].array { return events }
        guard let object = json.object else { return nil }
        if object.isEmpty || json["totalUsageEventsCount"].double == 0 { return [] }
        return nil
    }

    /// Billed cents across third-party usage events; 0 when none were billed.
    static func thirdPartyCents(fromUsageEvents events: [JSONValue]) -> Double {
        events.reduce(0) { $0 + (billedThirdPartyCents($1) ?? 0) }
    }

    /// What one usage event was billed, or nil when it doesn't count: a first-party (or unnamed)
    /// model, an included / free / errored kind, or nothing marking it as billed.
    /// Amount: `chargedCents`, else `usageBasedCosts`, else `tokenUsage.totalCents` only for
    /// USAGE_BASED kinds.
    static func billedThirdPartyCents(_ event: JSONValue) -> Double? {
        guard let model = event["model"].nonEmptyString, !isFirstPartyModel(model) else { return nil }
        let kind = event["kind"].string?.uppercased() ?? ""
        if ["INCLUDED", "FREE", "ERRORED"].contains(where: { kind.contains($0) }) { return nil }
        let charged = event["chargedCents"].double.flatMap { $0.isFinite ? $0 : nil }
        let usageBased = kind.contains("USAGE_BASED")
        guard usageBased || event["isChargeable"].bool == true || (charged ?? 0) > 0 else { return nil }
        let cents = charged
            ?? usageBasedCostCents(event["usageBasedCosts"])
            ?? (usageBased ? event["tokenUsage"]["totalCents"].double : nil)
        guard let cents, cents.isFinite else { return nil }
        return max(0, cents)
    }

    /// `usageBasedCosts` as cents. Cursor renders it as a dollar string ("$2.50"); bare numbers
    /// have no stated unit, so they're ignored rather than guessed at.
    static func usageBasedCostCents(_ value: JSONValue) -> Double? {
        guard let text = value.string?.trimmingCharacters(in: .whitespaces), text.hasPrefix("$"),
              let dollars = Double(text.dropFirst().replacingOccurrences(of: ",", with: "")) else { return nil }
        return dollars * 100
    }

    /// Fallback: billed cents over third-party models in a get-aggregated-usage-events response.
    /// Each third-party item must carry an explicit billed field (`chargedCents` /
    /// `usageBasedCents`); `totalCents` includes plan-covered cost, so any third-party item with
    /// only that makes the whole result nil. Nil too without an `aggregations` array.
    static func thirdPartyCents(fromAggregatedUsage json: JSONValue) -> Double? {
        guard let aggregations = json["aggregations"].array else { return nil }
        var sum: Double = 0
        for item in aggregations {
            guard let model = (item["modelIntent"].nonEmptyString ?? item["model"].nonEmptyString),
                  !isFirstPartyModel(model) else { continue }
            guard let cents = item["chargedCents"].double ?? item["usageBasedCents"].double,
                  cents.isFinite else { return nil }
            sum += cents
        }
        return sum
    }

    /// App Group key for the earliest GetSandUsageStatus `currentPeriodStart` seen while unified.
    static let unifiedSinceKey = "tmx.unifiedSince"

    /// The new unification anchor: the earlier of the stored anchor and the `currentPeriodStart`
    /// observed now. `currentPeriodStart` is the weekly pool's start and moves every week, so only
    /// the earliest one seen approximates when the account unified.
    static func unifiedSince(stored: Date?, observed: Date?) -> Date? {
        guard let stored else { return observed }
        guard let observed else { return stored }
        return min(stored, observed)
    }

    /// Start of the 3P spend window: the later of `unifiedSince` (see `unifiedSince(stored:observed:)`)
    /// and the start of the current calendar month in `calendar`'s time zone (the user's).
    /// grok.com's "Monthly additional usage" is per calendar month, and nothing before
    /// unification was billed at API rates under the X Subscription. Cursor's `billingCycleStart`
    /// predates unification on migrated accounts, so it is never used here. Nil when the start
    /// isn't before `now`.
    static func thirdPartyWindowStart(unifiedSince: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        let start = max(monthStart, unifiedSince ?? monthStart)
        return start < now ? start : nil
    }

    /// A date-only value ("2026-10-12") is that day's midnight in `calendar`'s time zone, so the
    /// "since" label shows the same day; anything else parses as usual.
    static func periodStartDate(_ value: JSONValue, calendar: Calendar) -> Date? {
        if let text = value.string?.trimmingCharacters(in: .whitespaces),
           text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        return value.date
    }

    /// get-aggregated-usage-events request body: int64 ms-epoch strings, as cursor.com sends them.
    static func aggregatedUsageBody(start: Date, end: Date) -> [String: Any] {
        [
            "teamId": -1,
            "startDate": String(Int64(start.timeIntervalSince1970 * 1000)),
            "endDate": String(Int64(end.timeIntervalSince1970 * 1000)),
        ]
    }

    /// get-filtered-usage-events request body: the aggregated body plus 1-based paging.
    static func filteredUsageBody(start: Date, end: Date, page: Int,
                                  pageSize: Int = usageEventsPageSize) -> [String: Any] {
        aggregatedUsageBody(start: start, end: end).merging(["page": page, "pageSize": pageSize]) { $1 }
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
