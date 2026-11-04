import XCTest
@testable import Core

final class WidgetSnapshotTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_762_182_000) // 2025-11-04 00:00 JST（= 11-03 15:00 UTC）

    private func snapshot() -> WidgetSnapshot {
        var points: [WidgetSnapshot.Point] = []
        for i in 0..<8 {
            let at: Date = base.addingTimeInterval(Double(i) * 900)
            let level: Double = 100 + Double(i) * 10
            points.append(WidgetSnapshot.Point(at: at, score: 50 + i * 5, tideRising: i < 4, tideLevelCm: level))
        }
        let events = [WidgetSnapshot.Event(at: base.addingTimeInterval(3600), label: "満潮", kind: "highTide"), WidgetSnapshot.Event(at: base.addingTimeInterval(7200), label: "マズメ", kind: "dawn")]
        return WidgetSnapshot(generatedAt: base, spotName: "函館港", points: points, events: events, isRecording: true, tackle: .bait)
    }

    func testJSONRoundTrip() throws {
        let s = snapshot()
        let back = try WidgetSnapshot.from(json: try s.jsonData())
        XCTAssertEqual(back, s)
    }

    func testPointAtUsesPreviousPoint() {
        let s = snapshot()
        XCTAssertEqual(s.point(at: base.addingTimeInterval(1000))?.score, 55)
        XCTAssertEqual(s.point(at: base.addingTimeInterval(-100))?.score, 50, "範囲より前は最初の点")
        XCTAssertEqual(s.point(at: base.addingTimeInterval(99_999))?.score, 85, "範囲より後は最後の点")
    }

    func testNextEventAndTimeline() {
        let s = snapshot()
        XCTAssertEqual(s.nextEvent(after: base.addingTimeInterval(3600))?.label, "マズメ")
        XCTAssertEqual(s.nextEvent(after: base, kinds: ["dawn", "dusk"])?.label, "マズメ")
        XCTAssertNil(s.nextEvent(after: base.addingTimeInterval(3600), kinds: ["highTide", "lowTide"]))
        // 古い形式（kind や天気の無い JSON）も読める
        let legacy = Data("""
        {"events":[{"at":"2025-11-04T00:00:00.000Z","label":"満潮"}],"generatedAt":"2025-11-04T00:00:00.000Z","isRecording":false,"points":[{"at":"2025-11-04T00:00:00.000Z","score":50}],"spotName":"x"}
        """.utf8)
        XCTAssertNoThrow(try WidgetSnapshot.from(json: legacy))
        XCTAssertNil(s.nextEvent(after: base.addingTimeInterval(8000)))
        let tl = s.timeline(from: base.addingTimeInterval(450), stepMinutes: 15, count: 100)
        XCTAssertEqual(tl.count, 7)
        XCTAssertEqual(tl.first?.at, base.addingTimeInterval(450))
        XCTAssertEqual(tl.first?.score, 50)
        XCTAssertEqual(tl[1].score, 55)
        XCTAssertEqual(s.tideRange(from: base, to: base.addingTimeInterval(7200)), 100...170)
    }

    func testPeakPlanFiresOneHourBeforeTodaysPeak() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        var points: [ScorePoint] = []
        for i in 0..<96 {
            let t: Date = base.addingTimeInterval(Double(i) * 900)
            let hour: Double = Double(i) / 4
            let score: Int = (hour >= 16 && hour < 18) ? 85 : 40
            points.append(ScorePoint(at: t, score: score, isForecast: false, confidence: .observed))
        }
        let plan = PeakNotificationPlanner.plan(points: points, now: base.addingTimeInterval(8 * 3600), timeZone: tz)
        XCTAssertEqual(plan?.fireAt, base.addingTimeInterval(15 * 3600))
        XCTAssertEqual(plan?.maxScore, 85)
        XCTAssertNil(PeakNotificationPlanner.plan(points: points, now: base.addingTimeInterval(15 * 3600 + 60), timeZone: tz), "通知時刻を過ぎていたら鳴らさない")
        XCTAssertNil(PeakNotificationPlanner.plan(points: points, now: base.addingTimeInterval(8 * 3600), threshold: 90, timeZone: tz))
        XCTAssertEqual(PeakNotificationPlanner.dayKey(for: base, timeZone: tz), "2025-11-4")
    }
}
