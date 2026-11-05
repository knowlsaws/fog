import XCTest
@testable import Core

final class PlanningTests: XCTestCase {
    let tz = TimeZone(identifier: "Asia/Tokyo")!
    func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))!
    }

    /// 明日 1 日分の推移。6〜8 時が 80、他は 40
    func tomorrowPoints() -> [ScorePoint] {
        let start = date(2026, 11, 6, 0)
        return stride(from: 0, through: 95, by: 1).map { i in
            let t = start.addingTimeInterval(Double(i) * 900)
            let h = Double(i) / 4
            return ScorePoint(at: t, score: (6..<8).contains(Int(h)) ? 80 : 40, isForecast: true, confidence: .forecast)
        }
    }

    func testBestWindowUsesPeaks() {
        let w = ScoreTimeline.bestWindow(tomorrowPoints())!
        XCTAssertEqual(w.maxScore, 80)
        XCTAssertEqual(w.start, date(2026, 11, 6, 6))
        XCTAssertEqual(w.end, date(2026, 11, 6, 7, 45))
    }

    func testBestWindowFallsBackToOneHourAroundMax() {
        let start = date(2026, 11, 6, 0)
        let pts = (0..<24).map { i in ScorePoint(at: start.addingTimeInterval(Double(i) * 3600), score: i == 10 ? 55 : 30, isForecast: false, confidence: .observed) }
        let w = ScoreTimeline.bestWindow(pts)!
        XCTAssertEqual(w.maxScore, 55)
        XCTAssertEqual(w.start, date(2026, 11, 6, 9))
        XCTAssertEqual(w.end, date(2026, 11, 6, 11))
    }

    func testDailyMax() {
        let pts = tomorrowPoints() + [ScorePoint(at: date(2026, 11, 7, 3), score: 91, isForecast: true, confidence: .forecast)]
        let m = ScoreTimeline.dailyMax(pts, timeZone: tz)
        XCTAssertEqual(m[date(2026, 11, 6, 0)], 80)
        XCTAssertEqual(m[date(2026, 11, 7, 0)], 91)
    }

    func testDailyBriefFiresAtTwentyTonight() {
        let now = date(2026, 11, 5, 14)
        let sun = SunTimes(civilDawn: date(2026, 11, 6, 5, 45), sunrise: date(2026, 11, 6, 6, 15), solarNoon: date(2026, 11, 6, 11, 20), sunset: date(2026, 11, 6, 16, 25), civilDusk: date(2026, 11, 6, 16, 55))
        let ext = [TideExtreme(kind: .high, at: date(2026, 11, 6, 6, 40), levelCm: 70)]
        let b = DailyBriefPlanner.plan(points: tomorrowPoints(), extremes: ext, sun: sun, airTemperatureC: 7.4, now: now, spotName: "函館港", timeZone: tz)!
        XCTAssertEqual(b.fireAt, date(2026, 11, 5, 20))
        XCTAssertEqual(b.maxScore, 80)
        XCTAssertEqual(b.title, "函館港 明日のベスト 6:00〜7:45")
        XCTAssertTrue(b.body.contains("釣れ率 80"))
        XCTAssertTrue(b.body.contains("朝マズメ 5:45〜"), b.body)
        XCTAssertTrue(b.body.contains("満潮 6:40"), b.body)
        XCTAssertTrue(b.body.contains("気温 7°"), b.body)
    }

    func testDailyBriefSkipsWhenPastFireTime() {
        XCTAssertNil(DailyBriefPlanner.plan(points: tomorrowPoints(), extremes: [], sun: nil, airTemperatureC: nil, now: date(2026, 11, 5, 21), spotName: "x", timeZone: tz))
    }

    func testSafetyPlanner() {
        let now = date(2026, 11, 5, 14)
        let alerts = SafetyPlanner.plan(now: now, sunset: date(2026, 11, 5, 16, 25), nextHighTide: date(2026, 11, 5, 18, 10), homeTimeMinutes: 17 * 60 + 30, timeZone: tz)
        XCTAssertEqual(alerts.map(\.kind), [.sunset, .highTide, .homeTime])
        XCTAssertEqual(alerts[0].fireAt, date(2026, 11, 5, 15, 55))
        XCTAssertEqual(alerts[1].fireAt, date(2026, 11, 5, 17, 10))
        XCTAssertEqual(alerts[2].fireAt, date(2026, 11, 5, 17, 30))
        XCTAssertTrue(alerts[0].body.contains("16:25"))
        // 過ぎたものは出さない
        let late = SafetyPlanner.plan(now: date(2026, 11, 5, 18), sunset: date(2026, 11, 5, 16, 25), nextHighTide: nil, homeTimeMinutes: 9 * 60, timeZone: tz)
        XCTAssertTrue(late.isEmpty)
    }

    func testSessionReview() {
        let start = date(2026, 11, 5, 6)
        let pts = (0..<16).map { i in ScorePoint(at: start.addingTimeInterval(Double(i) * 900), score: i < 8 ? 80 : 30, isForecast: false, confidence: .observed) }
        let r = SessionReview.evaluate(points: pts, catchTimes: [date(2026, 11, 5, 6, 30), date(2026, 11, 5, 9)], from: start, to: start.addingTimeInterval(4 * 3600))!
        XCTAssertEqual(r.meanScore, 55, accuracy: 0.01)
        XCTAssertEqual(r.meanScoreAtCatch!, 55, accuracy: 0.01)
        XCTAssertEqual(r.hitRate!, 0.5, accuracy: 0.01)
        XCTAssertEqual(r.catchScores.map { $0.1 }, [80, 30])
        XCTAssertTrue(r.verdict.hasPrefix("まずまず"))
        let none = SessionReview.evaluate(points: pts, catchTimes: [], from: start, to: start.addingTimeInterval(3600))!
        XCTAssertNil(none.hitRate)
        XCTAssertEqual(none.verdict, "釣果なし")
    }

    func testSceneTagger() {
        let t = SceneTagger.tags(from: [("pier", 0.6), ("sea", 0.9), ("sunset", 0.4), ("cloud", 0.3), ("rock", 0.1)])
        XCTAssertEqual(t.footing, "堤防")
        XCTAssertEqual(t.light, "朝夕")
        XCTAssertEqual(t.sky, "曇り")
        XCTAssertEqual(t.all, ["堤防", "朝夕", "曇り"])
        let empty = SceneTagger.tags(from: [("fish", 0.9)])
        XCTAssertTrue(empty.all.isEmpty)
        // 「tetrapod」は堤防より優先（信頼度が高い方）
        let tetra = SceneTagger.tags(from: [("tetrapod", 0.7), ("pier", 0.5)])
        XCTAssertEqual(tetra.footing, "テトラ")
    }

    func testTideCalendar() {
        let days = TideCalendar.days(from: date(2026, 11, 5, 15), days: 30, timeZone: tz)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days[0].dayStart, date(2026, 11, 5, 0))
        XCTAssertEqual(days[29].dayStart, date(2026, 12, 4, 0))
        // 大潮は 30 日の中に必ず 2 回以上ある
        XCTAssertGreaterThanOrEqual(days.filter { $0.tideName == .spring }.count, 4)
        for d in days { XCTAssertTrue((0..<30).contains(d.moonAge)) }
    }

    func testSessionAndCatchDecodeWithoutNewFields() throws {
        let s = Session(spotID: UUID(), startedAt: date(2026, 11, 5, 6))
        var data = try FogJSON.encode(s)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "pressureLog")
        data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try FogJSON.decode(Session.self, from: data)
        XCTAssertNil(decoded.pressureLog)
        let c = Catch(sessionID: s.id, at: s.startedAt, coordinate: SampleData.hakodate, species: "アイナメ", speciesConfidence: 0.9, sceneTags: ["堤防"])
        let cd = try FogJSON.decode(Catch.self, from: try FogJSON.encode(c))
        XCTAssertEqual(cd.sceneTags, ["堤防"])
    }
}
