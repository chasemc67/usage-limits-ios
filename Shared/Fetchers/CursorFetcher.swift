import Foundation

struct CursorFetcher: ServiceFetcher {
    static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let aggregatedUsageURL = URL(string: "https://cursor.com/api/dashboard/get-aggregated-usage-events")!
    static let filteredUsageURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!

    func fetch() async -> ServiceSnapshot {
        guard let raw = TokenStore.cursorSessionToken,
              let cookie = CursorAuth.normalizedCookieValue(raw) else {
            return .failure(.cursor, ServiceError.notSignedIn)
        }
        let jwt = CursorAuth.jwt(from: cookie)

        async let summaryTask = Self.capture { try await Self.fetchSummary(cookie: cookie) }
        async let sandTask = Self.capture {
            guard let jwt else { throw ServiceError.notSignedIn }
            return try await GrokBotFetcher.fetchStatus(jwt: jwt)
        }
        let (summaryResult, sandResult) = await (summaryTask, sandTask)

        var summary: JSONValue?
        var summaryError: Error?
        switch summaryResult {
        case .success(let json): summary = json
        case .failure(let error): summaryError = error
        }
        let sand = try? sandResult.get()

        if UnifiedPlan.isUnified(summary: summary, sand: sand) {
            return await unifiedSnapshot(cookie: cookie, summary: summary, sand: sandResult)
        }

        var windows: [UsageWindow] = []
        var extras: [String] = []
        var cycleStart = summary?["billingCycleStart"].date
        var cycleEnd = summary?["billingCycleEnd"].date

        if let summary {
            if let membership = UnifiedPlan.planDisplayName(summary["membershipType"].nonEmptyString) {
                extras.append("Plan: \(membership)")
            }
            windows = Self.planWindows(summary["individualUsage"]["plan"], messages: nil,
                                       start: cycleStart, end: cycleEnd)

            let onDemand = summary["individualUsage"]["onDemand"]
            if let used = onDemand["used"].double {
                let enabled = onDemand["enabled"].bool ?? true
                if let limit = onDemand["limit"].double, limit > 0 {
                    extras.append("On-demand: \(Money.dollars(cents: used)) of \(Money.dollars(cents: limit))")
                } else if used > 0 || enabled {
                    extras.append("On-demand: \(Money.dollars(cents: used)) spent")
                }
            }
        }

        // Fallback: some accounts have no individualUsage.plan in the summary.
        if windows.isEmpty, let jwt {
            do {
                let period = try await fetchCurrentPeriod(jwt: jwt)
                cycleStart = cycleStart ?? period["billingCycleStart"].date
                cycleEnd = cycleEnd ?? period["billingCycleEnd"].date
                let messages = Messages(
                    total: period["displayMessage"].string,
                    auto: period["autoModelSelectedDisplayMessage"].string,
                    api: period["namedModelSelectedDisplayMessage"].string)
                windows = Self.planWindows(period["planUsage"], messages: messages,
                                           start: cycleStart, end: cycleEnd)

                let spend = period["spendLimitUsage"]
                if let limit = spend["individualLimit"].double, limit > 0 {
                    let remaining = spend["individualRemaining"].double ?? limit
                    let used = spend["individualUsed"].double ?? max(0, limit - remaining)
                    extras.append("On-demand: \(Money.dollars(cents: used)) of \(Money.dollars(cents: limit)) (\(Money.dollars(cents: remaining)) left)")
                }
                if summary == nil, let membership = UnifiedPlan.planDisplayName(period["membershipType"].nonEmptyString) {
                    extras.append("Plan: \(membership)")
                }
            } catch {
                if summary == nil {
                    return .failure(.cursor, summaryError ?? error)
                }
            }
        }

        if windows.isEmpty {
            if summary == nil {
                return .failure(.cursor, summaryError ?? ServiceError.notSignedIn)
            }
            return ServiceSnapshot(kind: .cursor, windows: [], extras: extras, fetchedAt: Date(),
                                   error: "No plan usage reported for this account")
        }

        return ServiceSnapshot(kind: .cursor, windows: windows, extras: extras, fetchedAt: Date(), error: nil,
                               unified: false)
    }

    // MARK: - Unified (X Subscription)

    /// One shared weekly pool (mirrored from GetSandUsageStatus) plus third-party API spend.
    /// The billing-cycle pools and on-demand lines don't apply to unified accounts.
    private func unifiedSnapshot(cookie: String, summary: JSONValue?,
                                 sand: Result<JSONValue, Error>) async -> ServiceSnapshot {
        let status: JSONValue
        switch sand {
        case .success(let json):
            status = json
        case .failure(let error):
            return ServiceSnapshot(kind: .cursor, windows: [], extras: UnifiedPlan.planExtras(summary: summary, sand: nil),
                                   fetchedAt: Date(), error: ServiceError.message(for: error), unified: true)
        }

        // 3P spend is fetched only here, so it depends on unified detection succeeding.
        var thirdPartyCents: Double?
        var thirdPartySince: Date?
        let now = Date()
        let defaults = AppGroup.defaults
        let stored = defaults.object(forKey: UnifiedPlan.unifiedSinceKey) as? Date
        let observed = UnifiedPlan.periodStartDate(status["currentPeriodStart"], calendar: .current)
        let unifiedSince = UnifiedPlan.unifiedSince(stored: stored, observed: observed)
        if let unifiedSince, unifiedSince != stored {
            defaults.set(unifiedSince, forKey: UnifiedPlan.unifiedSinceKey)
        }
        if let start = UnifiedPlan.thirdPartyWindowStart(unifiedSince: unifiedSince, now: now) {
            thirdPartyCents = await Self.fetchThirdPartyCents(cookie: cookie, start: start, end: now)
            if thirdPartyCents != nil { thirdPartySince = start }
        }

        return UnifiedPlan.cursorSnapshot(summary: summary, sand: status, thirdPartyCents: thirdPartyCents,
                                          thirdPartySince: thirdPartySince)
    }

    // MARK: - Requests

    private static func capture(_ operation: () async throws -> JSONValue) async -> Result<JSONValue, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private static func dashboardHeaders(cookie: String) -> [String: String] {
        [
            "Cookie": "\(CursorAuth.cookieName)=\(cookie)",
            "Origin": "https://cursor.com",
            "Referer": "https://cursor.com/dashboard",
            "User-Agent": HTTP.browserUserAgent,
        ]
    }

    /// Billed cents on third-party models (API rates) between `start` and `end`: from per-event
    /// usage when available, else from aggregated usage if it reports billed amounts; nil when
    /// neither can say what was billed.
    private static func fetchThirdPartyCents(cookie: String, start: Date, end: Date) async -> Double? {
        if let events = try? await fetchUsageEvents(cookie: cookie, start: start, end: end) {
            return UnifiedPlan.thirdPartyCents(fromUsageEvents: events)
        }
        guard let json = try? await postDashboard(aggregatedUsageURL, cookie: cookie,
                                                  body: UnifiedPlan.aggregatedUsageBody(start: start, end: end))
        else { return nil }
        return UnifiedPlan.thirdPartyCents(fromAggregatedUsage: json)
    }

    /// All usage events between `start` and `end`, up to `UnifiedPlan.usageEventsMaxPages` pages.
    /// Throws if any page fails, so a partial list is never summed.
    private static func fetchUsageEvents(cookie: String, start: Date, end: Date) async throws -> [JSONValue] {
        var events: [JSONValue] = []
        for page in 1...UnifiedPlan.usageEventsMaxPages {
            let json = try await postDashboard(filteredUsageURL, cookie: cookie,
                                               body: UnifiedPlan.filteredUsageBody(start: start, end: end, page: page))
            guard let pageEvents = UnifiedPlan.usageEvents(fromFilteredUsage: json) else {
                throw ServiceError.invalidResponse("get-filtered-usage-events")
            }
            events += pageEvents
            let total = json["totalUsageEventsCount"].int ?? events.count
            if pageEvents.count < UnifiedPlan.usageEventsPageSize || events.count >= total { break }
        }
        return events
    }

    private static func postDashboard(_ url: URL, cookie: String, body: [String: Any]) async throws -> JSONValue {
        var request = HTTP.request(url, method: "POST", headers: dashboardHeaders(cookie: cookie))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result = try await HTTP.send(request)
        guard result.isSuccess, let json = result.json else { throw result.serviceError() }
        return json
    }

    static func fetchSummary(cookie: String) async throws -> JSONValue {
        let request = HTTP.request(usageSummaryURL, headers: dashboardHeaders(cookie: cookie))
        let result = try await HTTP.send(request)
        if result.status == 401 || result.status == 403 {
            throw ServiceError.sessionExpired
        }
        guard result.isSuccess else { throw result.serviceError() }
        guard let json = result.json, json.object != nil else {
            throw ServiceError.invalidResponse("usage-summary")
        }
        return json
    }

    private func fetchCurrentPeriod(jwt: String) async throws -> JSONValue {
        let result = try await HTTP.send(CursorAuth.dashboardRequest("GetCurrentPeriodUsage", jwt: jwt))
        if result.status == 401 || result.status == 403 {
            throw ServiceError.sessionExpired
        }
        guard result.isSuccess else { throw result.serviceError() }
        guard let json = result.json, json.object != nil else {
            throw ServiceError.invalidResponse("GetCurrentPeriodUsage")
        }
        return json
    }

    // MARK: - Parsing

    struct Messages {
        var total: String?
        var auto: String?
        var api: String?
    }

    static func planWindows(_ plan: JSONValue, messages: Messages?, start: Date?, end: Date?) -> [UsageWindow] {
        guard plan.object != nil || messages != nil else { return [] }

        var windowSeconds: Int?
        if let start, let end, end > start {
            windowSeconds = Int(end.timeIntervalSince(start))
        }

        let autoPercent = plan["autoPercentUsed"].double ?? PercentText.parse(messages?.auto)
        let apiPercent = plan["apiPercentUsed"].double ?? PercentText.parse(messages?.api)

        let usedCents = plan["used"].double ?? plan["includedSpend"].double ?? plan["totalSpend"].double
        let limitCents = plan["limit"].double
        var totalPercent = plan["totalPercentUsed"].double
        if totalPercent == nil, let usedCents, let limitCents, limitCents > 0 {
            totalPercent = usedCents / limitCents * 100
        }
        if totalPercent == nil {
            totalPercent = PercentText.parse(messages?.total)
        }

        var windows: [UsageWindow] = []
        if let autoPercent {
            windows.append(UsageWindow(id: "cursor.auto", label: "Cursor Models (Auto)", usedPercent: autoPercent,
                                       resetsAt: end, windowSeconds: windowSeconds))
        }
        if let apiPercent {
            windows.append(UsageWindow(id: "cursor.api", label: "Other Models (API)", usedPercent: apiPercent,
                                       resetsAt: end, windowSeconds: windowSeconds))
        }
        if let totalPercent {
            var detail: String?
            if let usedCents, let limitCents, limitCents > 0 {
                detail = "\(Money.dollars(cents: usedCents)) of \(Money.dollars(cents: limitCents)) used"
            } else if let message = messages?.total, !message.isEmpty {
                detail = message
            }
            windows.append(UsageWindow(id: "cursor.total", label: "Total included", usedPercent: totalPercent,
                                       resetsAt: end, windowSeconds: windowSeconds, detail: detail))
        }
        return windows
    }
}
