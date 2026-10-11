import Foundation

struct CursorFetcher: ServiceFetcher {
    static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    func fetch() async -> ServiceSnapshot {
        guard let raw = TokenStore.cursorSessionToken,
              let cookie = CursorAuth.normalizedCookieValue(raw) else {
            return .failure(.cursor, ServiceError.notSignedIn)
        }
        let jwt = CursorAuth.jwt(from: cookie)

        var summary: JSONValue?
        var summaryError: Error?
        do {
            summary = try await fetchSummary(cookie: cookie)
        } catch {
            summaryError = error
        }

        var windows: [UsageWindow] = []
        var extras: [String] = []
        var cycleStart = summary?["billingCycleStart"].date
        var cycleEnd = summary?["billingCycleEnd"].date

        if let summary {
            if let membership = summary["membershipType"].nonEmptyString {
                extras.append("Plan: \(membership.capitalized)")
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
                if summary == nil, let membership = period["membershipType"].nonEmptyString {
                    extras.append("Plan: \(membership.capitalized)")
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

        return ServiceSnapshot(kind: .cursor, windows: windows, extras: extras, fetchedAt: Date(), error: nil)
    }

    // MARK: - Requests

    private func fetchSummary(cookie: String) async throws -> JSONValue {
        let request = HTTP.request(Self.usageSummaryURL, headers: [
            "Cookie": "\(CursorAuth.cookieName)=\(cookie)",
            "Origin": "https://cursor.com",
            "Referer": "https://cursor.com/dashboard",
            "User-Agent": HTTP.browserUserAgent,
        ])
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
