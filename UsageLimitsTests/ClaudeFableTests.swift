import XCTest

/// Claude OAuth usage: model-scoped weekly pools in `limits[]` (Fable) plus legacy buckets.
final class ClaudeFableTests: XCTestCase {
    static func json(_ text: String) -> JSONValue {
        try! JSONValue.parse(Data(text.utf8))
    }

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testFableParsedAtZeroPercent() throws {
        let snapshot = ClaudeFetcher.snapshot(from: Self.json("""
        {
          "five_hour": { "utilization": 16, "resets_at": "2026-10-13T18:00:00Z" },
          "seven_day": { "utilization": 83, "resets_at": "2026-10-19T12:00:00Z" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "limits": [
            { "kind": "session", "percent": 99, "resets_at": "2026-10-13T18:00:00Z", "is_active": true },
            {
              "kind": "weekly_scoped",
              "percent": 0,
              "resets_at": "2026-10-19T12:00:00Z",
              "is_active": true,
              "scope": { "model": { "id": null, "display_name": "Fable" } }
            }
          ]
        }
        """))

        XCTAssertNil(snapshot.error)
        XCTAssertEqual(snapshot.windows.map(\.id), [
            "claude.five_hour", "claude.seven_day", "claude.weekly_scoped.fable",
        ])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [16, 83, 0])
        let fable = try XCTUnwrap(snapshot.windows.last)
        XCTAssertEqual(fable.label, "Weekly (Fable only)")
        XCTAssertEqual(fable.windowSeconds, 604_800)
        XCTAssertEqual(fable.resetsAt, Self.date("2026-10-19T12:00:00Z"))
        XCTAssertEqual(snapshot.windows[0].windowSeconds, 18_000)
    }

    func testInactiveScopedEntriesAreSkipped() throws {
        let snapshot = ClaudeFetcher.snapshot(from: Self.json("""
        {
          "five_hour": { "utilization": 10, "resets_at": "2026-10-13T18:00:00Z" },
          "seven_day_opus": { "utilization": 9, "resets_at": "2026-10-19T12:00:00Z" },
          "limits": [
            {
              "kind": "weekly_scoped", "percent": 40, "resets_at": "2026-10-19T12:00:00Z",
              "is_active": false, "scope": { "model": { "display_name": "Fable" } }
            },
            {
              "kind": "weekly_scoped", "percent": 5, "resets_at": "2026-10-19T12:00:00Z",
              "is_active": true, "scope": { "model": { "id": null } }
            },
            {
              "kind": "weekly_scoped", "percent": 80, "resets_at": "2026-10-19T12:00:00Z",
              "is_active": false, "scope": { "model": { "display_name": "Opus" } }
            },
            {
              "kind": "weekly_scoped", "percent": 12, "resets_at": "2026-10-19T12:00:00Z",
              "scope": { "model": { "display_name": "Haiku" } }
            }
          ]
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), [
            "claude.five_hour", "claude.weekly_scoped.haiku", "claude.seven_day_opus",
        ])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [10, 12, 9])
        XCTAssertFalse(snapshot.windows.contains { $0.label.contains("Fable") })
    }

    func testLegacyOnlyPayloadStillWorks() {
        let snapshot = ClaudeFetcher.snapshot(from: Self.json("""
        {
          "five_hour": { "utilization": 37, "resets_at": "2026-10-13T20:00:00Z" },
          "seven_day": { "utilization": 25, "resets_at": "2026-10-18T00:00:00Z" },
          "seven_day_opus": { "utilization": 11, "resets_at": "2026-10-18T00:00:00Z" },
          "seven_day_sonnet": { "utilization": 4, "resets_at": "2026-10-18T00:00:00Z" }
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), [
            "claude.five_hour", "claude.seven_day", "claude.seven_day_opus", "claude.seven_day_sonnet",
        ])
        XCTAssertEqual(snapshot.windows.map(\.label), [
            "5-hour", "Weekly (all models)", "Weekly Opus", "Weekly Sonnet",
        ])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [37, 25, 11, 4])
        XCTAssertEqual(snapshot.windows.map(\.windowSeconds), [18_000, 604_800, 604_800, 604_800])
        XCTAssertNil(snapshot.error)
    }

    func testBackfillFromSessionAndWeeklyAll() throws {
        let snapshot = ClaudeFetcher.snapshot(from: Self.json("""
        {
          "limits": [
            { "kind": "session", "percent": 16, "resets_at": "2026-10-13T18:00:00Z", "is_active": true },
            { "kind": "weekly_all", "percent": 83, "resets_at": "2026-10-19T12:00:00Z" },
            {
              "kind": "weekly_scoped", "percent": 0, "resets_at": "2026-10-19T12:00:00Z",
              "scope": { "model": { "display_name": "Fable" } }
            },
            { "kind": "session", "percent": 99, "is_active": false }
          ]
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), [
            "claude.five_hour", "claude.seven_day", "claude.weekly_scoped.fable",
        ])
        XCTAssertEqual(snapshot.windows.map(\.label), [
            "5-hour", "Weekly (all models)", "Weekly (Fable only)",
        ])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [16, 83, 0])
        XCTAssertEqual(snapshot.windows.map(\.windowSeconds), [18_000, 604_800, 604_800])
        let session = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(session.resetsAt, Self.date("2026-10-13T18:00:00Z"))
    }

    func testWeeklyScopedLabelText() {
        let snapshot = ClaudeFetcher.snapshot(from: Self.json("""
        {
          "limits": [
            {
              "kind": "weekly_scoped", "percent": 0, "resets_at": "2026-10-19T12:00:00Z",
              "scope": { "model": { "display_name": "Fable" } }
            },
            {
              "kind": "weekly_scoped", "percent": 3, "resets_at": "2026-10-19T12:00:00Z",
              "is_active": true, "scope": { "model": { "display_name": "Claude-Haiku" } }
            }
          ]
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.label), [
            "Weekly (Fable only)", "Weekly (Claude-Haiku only)",
        ])
        XCTAssertEqual(snapshot.windows.map(\.id), [
            "claude.weekly_scoped.fable", "claude.weekly_scoped.claude_haiku",
        ])
    }

    func testScopedReplacesMatchingLegacyBucket() throws {
        let snapshot = ClaudeFetcher.snapshot(from: Self.json("""
        {
          "five_hour": { "utilization": 1, "resets_at": "2026-10-13T18:00:00Z" },
          "seven_day": { "utilization": 2, "resets_at": "2026-10-19T12:00:00Z" },
          "seven_day_opus": { "utilization": 50, "resets_at": "2026-10-19T12:00:00Z" },
          "seven_day_sonnet": { "utilization": 4, "resets_at": "2026-10-19T12:00:00Z" },
          "limits": [
            {
              "kind": "weekly_scoped", "percent": 7, "resets_at": "2026-10-19T12:00:00Z",
              "scope": { "model": { "display_name": "Opus" } }
            }
          ]
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), [
            "claude.five_hour", "claude.seven_day", "claude.weekly_scoped.opus", "claude.seven_day_sonnet",
        ])
        let opus = try XCTUnwrap(snapshot.windows.first { $0.id == "claude.weekly_scoped.opus" })
        XCTAssertEqual(opus.label, "Weekly (Opus only)")
        XCTAssertEqual(opus.usedPercent, 7)
        XCTAssertEqual(snapshot.windows.last?.label, "Weekly Sonnet")
        XCTAssertEqual(snapshot.windows.last?.usedPercent, 4)
    }
}
