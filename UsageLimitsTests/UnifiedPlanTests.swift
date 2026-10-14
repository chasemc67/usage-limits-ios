import XCTest

/// Fixtures mirror a live unified (X Subscription) account, Oct 2026.
final class UnifiedPlanTests: XCTestCase {
    static func json(_ text: String) -> JSONValue {
        try! JSONValue.parse(Data(text.utf8))
    }

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// usage-summary: membershipType "unified_ultra" with a populated plan block ($0.00 of $553.95).
    static let unifiedSummary = json("""
    {
      "billingCycleStart": "2026-10-01T00:00:00.000Z",
      "billingCycleEnd": "2026-11-01T00:00:00.000Z",
      "membershipType": "unified_ultra",
      "isUnlimited": false,
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 0,
          "limit": 55395,
          "remaining": 55395,
          "autoPercentUsed": 0,
          "apiPercentUsed": 0,
          "totalPercentUsed": 0
        },
        "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
      }
    }
    """)

    /// The same account as proto3 JSON would send it: zero values omitted, no billingCycleStart.
    static let unifiedSummaryOmittingZeros = json("""
    {
      "billingCycleEnd": "2026-11-01T00:00:00Z",
      "membershipType": "unified_ultra",
      "individualUsage": { "plan": { "limit": 55395 } }
    }
    """)

    static let unifiedSand = json("""
    {
      "usagePercent": 16,
      "nextResetTimestampUtc": "2026-10-20T02:46:00Z",
      "currentPeriodStart": "2026-10-12",
      "grokPlanLabel": "Grok Bot Plan",
      "cursorPlanName": "Ultra",
      "onDemandSettings": { "enabled": false }
    }
    """)

    static let proSummary = json("""
    {
      "billingCycleStart": "2026-10-01T00:00:00.000Z",
      "billingCycleEnd": "2026-11-01T00:00:00.000Z",
      "membershipType": "pro",
      "individualUsage": {
        "plan": { "used": 1200, "limit": 2000, "autoPercentUsed": 12, "apiPercentUsed": 40, "totalPercentUsed": 60 },
        "onDemand": { "enabled": true, "used": 0 }
      }
    }
    """)

    static let proSand = json("""
    {
      "usagePercent": 5,
      "nextResetTimestampUtc": "2026-10-20T02:46:00Z",
      "grokPlanLabel": "Grok Bot Plan",
      "cursorPlanName": "Pro"
    }
    """)

    static let aggregatedUsage = json("""
    {
      "aggregations": [
        { "modelIntent": "claude-4.5-opus", "inputTokens": "1000", "outputTokens": "200", "totalCents": "1234" },
        { "modelIntent": "grok-4.7", "totalCents": 500 },
        { "modelIntent": "composer-2.5", "totalCents": 100 },
        { "modelIntent": "auto", "totalCents": 50 }
      ],
      "totalInputTokens": "1000",
      "totalCostCents": 1884
    }
    """)

    /// The snapshots a refresh of the live account stores.
    static func unifiedSnapshots(thirdPartyCents: Double? = 1234) -> [ServiceKind: ServiceSnapshot] {
        [
            .cursor: UnifiedPlan.cursorSnapshot(summary: unifiedSummary, sand: unifiedSand,
                                                thirdPartyCents: thirdPartyCents,
                                                thirdPartySince: date("2026-10-01T00:00:00Z")),
            .grokBot: GrokBotFetcher.snapshot(from: unifiedSand,
                                              unified: UnifiedPlan.isUnified(summary: unifiedSummary, sand: unifiedSand)),
        ]
    }

    // MARK: - Detection

    func testUnifiedUltraIsUnifiedDespitePlanPools() {
        XCTAssertTrue(UnifiedPlan.planHasPercentages(Self.unifiedSummary["individualUsage"]["plan"]))
        XCTAssertTrue(UnifiedPlan.isUnified(summary: Self.unifiedSummary, sand: Self.unifiedSand))
        XCTAssertTrue(UnifiedPlan.isUnified(summary: Self.unifiedSummaryOmittingZeros, sand: Self.unifiedSand))
        // Detected from usage-summary alone, e.g. when GetSandUsageStatus failed.
        XCTAssertTrue(UnifiedPlan.isUnified(summary: Self.unifiedSummary, sand: nil))
    }

    func testUnifiedMatchesAnyCase() {
        XCTAssertTrue(UnifiedPlan.isXSubscription("Unified_Ultra"))
        XCTAssertTrue(UnifiedPlan.isXSubscription("UNIFIED"))
        XCTAssertTrue(UnifiedPlan.isXSubscription("The X Subscription"))
        XCTAssertFalse(UnifiedPlan.isXSubscription("Max subscription"))
        XCTAssertFalse(UnifiedPlan.isXSubscription("ultra"))
    }

    func testProAccountStaysNonUnified() {
        XCTAssertFalse(UnifiedPlan.isUnified(summary: Self.proSummary, sand: Self.proSand))
        XCTAssertFalse(UnifiedPlan.isUnified(summary: Self.proSummary, sand: nil))
        XCTAssertFalse(UnifiedPlan.isUnified(summary: nil, sand: Self.proSand))
    }

    // MARK: - xAI section

    func testXAISectionReplacesCursorAndGrokBot() {
        let snapshots = Self.unifiedSnapshots()
        XCTAssertTrue(UnifiedPlan.isUnified(snapshots))
        let kinds = UnifiedPlan.sectionKinds(snapshots)
        XCTAssertEqual(kinds.first, .xai)
        XCTAssertFalse(kinds.contains(.cursor))
        XCTAssertFalse(kinds.contains(.grokBot))
    }

    func testXAISnapshotSharedWindow() throws {
        let xai = try XCTUnwrap(UnifiedPlan.xaiSnapshot(Self.unifiedSnapshots()))
        XCTAssertEqual(xai.kind, .xai)
        XCTAssertEqual(xai.windows.count, 1)
        let window = try XCTUnwrap(xai.windows.first)
        XCTAssertEqual(window.id, UnifiedPlan.cursorSharedWindowID)
        XCTAssertEqual(window.label, UnifiedPlan.sharedWindowLabel)
        XCTAssertEqual(window.usedPercent, 16)
        XCTAssertEqual(window.resetsAt, Self.date("2026-10-20T02:46:00Z"))
        XCTAssertEqual(window.windowSeconds, 604_800)
        XCTAssertEqual(xai.thirdPartyCents, 1234)
    }

    func testXAISnapshotHidesCursorPlanPools() throws {
        let xai = try XCTUnwrap(UnifiedPlan.xaiSnapshot(Self.unifiedSnapshots()))
        let ids = Set(xai.windows.map(\.id))
        XCTAssertTrue(ids.isDisjoint(with: ["cursor.auto", "cursor.api", "cursor.total"]))
        XCTAssertFalse(xai.extras.contains { $0.hasPrefix("On-demand") })
    }

    func testPlanLinePrettified() throws {
        let xai = try XCTUnwrap(UnifiedPlan.xaiSnapshot(Self.unifiedSnapshots()))
        XCTAssertEqual(xai.extras, ["Plan: Ultra"])
        XCTAssertEqual(UnifiedPlan.planDisplayName("unified_ultra"), "Ultra")
        XCTAssertEqual(UnifiedPlan.planDisplayName("pro"), "Pro")
        XCTAssertNil(UnifiedPlan.planDisplayName("unified"))
        // Falls back to sand's cursorPlanName when membershipType says only "unified".
        XCTAssertEqual(UnifiedPlan.planName(summary: Self.json(#"{"membershipType": "unified"}"#),
                                            sand: Self.unifiedSand), "Ultra")
    }

    func testXAIFallsBackToGrokBotWithCursorPlanLine() throws {
        var snapshots = Self.unifiedSnapshots()
        snapshots[.cursor] = ServiceSnapshot(kind: .cursor, windows: [], extras: ["Plan: Ultra"], fetchedAt: Date(),
                                             error: "timed out", unified: true)
        let xai = try XCTUnwrap(UnifiedPlan.xaiSnapshot(snapshots))
        XCTAssertEqual(xai.windows.first?.usedPercent, 16)
        XCTAssertEqual(xai.extras, ["Plan: Ultra"])
    }

    // MARK: - Third-party spend

    func testThirdPartyCentsSumsOnlyThirdPartyModels() {
        XCTAssertEqual(UnifiedPlan.thirdPartyCents(fromAggregatedUsage: Self.aggregatedUsage), 1234)
    }

    func testThirdPartyCentsMissingAggregationsIsNil() {
        XCTAssertNil(UnifiedPlan.thirdPartyCents(fromAggregatedUsage: Self.json(#"{"totalCostCents": 0}"#)))
    }

    func testThirdPartyCentsEmptyAggregationsIsZero() {
        XCTAssertEqual(UnifiedPlan.thirdPartyCents(fromAggregatedUsage: Self.json(#"{"aggregations": []}"#)), 0)
    }

    func testFirstPartyModelFilter() {
        for model in ["grok-4.7", "composer-2.5", "auto", "default", "cursor-small", "xai/grok-code", "Auto"] {
            XCTAssertTrue(UnifiedPlan.isFirstPartyModel(model), model)
        }
        for model in ["claude-4.5-opus", "gpt-5", "gemini-3-pro", "autocoder-pro", "o3-default-mode"] {
            XCTAssertFalse(UnifiedPlan.isFirstPartyModel(model), model)
        }
    }

    func testThirdPartyWindowStart() {
        let now = Self.date("2026-10-13T12:00:00Z")
        XCTAssertEqual(UnifiedPlan.thirdPartyWindowStart(summary: Self.unifiedSummary, sand: Self.unifiedSand, now: now),
                       Self.date("2026-10-01T00:00:00Z"))
        // No billingCycleStart: one month before billingCycleEnd.
        XCTAssertEqual(UnifiedPlan.thirdPartyWindowStart(summary: Self.unifiedSummaryOmittingZeros,
                                                         sand: Self.unifiedSand, now: now),
                       Self.date("2026-10-01T00:00:00Z"))
    }

    func testAggregatedUsageBodyUsesMillisecondStrings() {
        let body = UnifiedPlan.aggregatedUsageBody(start: Self.date("2026-10-01T00:00:00Z"),
                                                   end: Self.date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(body["startDate"] as? String, "1790812800000")
        XCTAssertEqual(body["endDate"] as? String, "1791892800000")
        XCTAssertEqual(body["teamId"] as? Int, -1)
    }
}
