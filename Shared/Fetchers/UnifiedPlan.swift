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
