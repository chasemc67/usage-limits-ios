import Foundation

struct GrokBotFetcher: ServiceFetcher {
    func fetch() async -> ServiceSnapshot {
        guard let raw = TokenStore.cursorSessionToken,
              let cookie = CursorAuth.normalizedCookieValue(raw),
              let jwt = CursorAuth.jwt(from: cookie) else {
            return .failure(.grokBot, ServiceError.notSignedIn)
        }

        // usage-summary is only needed to detect a unified (X Subscription) account.
        async let summary: JSONValue? = try? await CursorFetcher.fetchSummary(cookie: cookie)
        do {
            let json = try await Self.fetchStatus(jwt: jwt)
            let unified = UnifiedPlan.isUnified(summary: await summary, sand: json)
            return Self.snapshot(from: json, unified: unified)
        } catch {
            return .failure(.grokBot, error)
        }
    }

    static func fetchStatus(jwt: String) async throws -> JSONValue {
        let result = try await HTTP.send(CursorAuth.dashboardRequest("GetSandUsageStatus", jwt: jwt))
        if result.status == 401 || result.status == 403 {
            throw ServiceError.sessionExpired
        }
        guard result.isSuccess else { throw result.serviceError() }
        guard let json = result.json, json.object != nil else {
            throw ServiceError.invalidResponse("GetSandUsageStatus")
        }
        return json
    }

    static func snapshot(from json: JSONValue, unified: Bool = false) -> ServiceSnapshot {
        let window = weeklyWindow(from: json, id: "grok.weekly",
                                  label: unified ? UnifiedPlan.sharedWindowLabel : "Weekly")

        var extras: [String] = []
        if let plan = json["grokPlanLabel"].nonEmptyString {
            extras.append("Plan: \(plan)")
        }
        if let cursorPlan = json["cursorPlanName"].nonEmptyString {
            extras.append("Cursor plan: \(cursorPlan)")
        }
        if !unified {
            let onDemand = json["onDemandSettings"]["enabled"].bool ?? false
            extras.append("On-demand: \(onDemand ? "enabled" : "disabled")")
        }
        if json["hasAvailableUsage"].bool == false {
            extras.append("No usage available until reset")
        }

        return ServiceSnapshot(kind: .grokBot, windows: [window], extras: extras, fetchedAt: Date(), error: nil,
                               unified: unified)
    }

    /// The weekly pool from a GetSandUsageStatus response. On unified accounts this is the
    /// pool shared by Grok, Grok Bot and Cursor, so Cursor mirrors it under its own id.
    static func weeklyWindow(from json: JSONValue, id: String, label: String) -> UsageWindow {
        // proto3 JSON omits zero values, so a missing usagePercent means 0.
        let used = json["usagePercent"].double ?? 0
        let periodStart = json["currentPeriodStart"].date

        var detail: String?
        if let periodStart {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            detail = "Period started \(formatter.string(from: periodStart))"
        }

        return UsageWindow(id: id,
                           label: label,
                           usedPercent: used,
                           resetsAt: json["nextResetTimestampUtc"].date,
                           windowSeconds: 604_800,
                           detail: detail)
    }
}
