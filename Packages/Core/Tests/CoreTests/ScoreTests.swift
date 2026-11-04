import Foundation
import XCTest
@testable import Core

/// L7 受け入れ条件: 典型条件が妥当、ボウズを学習に使っても破綻しない、1 日分の推移を 50 ms 以内。
final class ScoreEngineL7Tests: XCTestCase {
    let hakodate = Coordinate(latitude: 41.7822, longitude: 140.7192)
    let jst = TimeZone(identifier: "Asia/Tokyo")!

    func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = jst
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))!
    }

    func env(at: Date, wind: Double, tideRate: Double, tideName: String = "中潮", wave: Double? = 0.3, sst: Double? = 14, trend: Double? = -1) -> EnvSnapshot {
        var e = EnvSnapshot(at: at, coordinate: hakodate, isForecast: false)
        e.windSpeedMS = wind; e.tideRateCmPerHour = tideRate; e.tideName = tideName
        e.waveHeightM = wave; e.seaSurfaceTempC = sst; e.pressureTrend3hHPa = trend
        e.airTemperatureC = 12; e.moonAge = 7
        return e
    }

    func testDawnRisingTideLightWindIsHigh() {
        // 2026-10-18 函館の日の出は 5:52 → 5:40 は朝マズメ
        let at = date(2026, 10, 18, 5, 40)
        let r = ScoreEngine().score(ScoreInput(at: at, coordinate: hakodate, env: env(at: at, wind: 2, tideRate: 12)))
        XCTAssertGreaterThanOrEqual(r.score, 80, "\(r.breakdown)")
        XCTAssertTrue(r.breakdown.contains { $0.factor == .light && $0.points > 0 })
        XCTAssertEqual(r.confidence, .observed)
    }

    func testMiddaySlackTideStrongWindIsLow() {
        let at = date(2026, 10, 18, 12, 0)
        let r = ScoreEngine().score(ScoreInput(at: at, coordinate: hakodate, env: env(at: at, wind: 10, tideRate: 1, wave: 1.8)))
        XCTAssertLessThanOrEqual(r.score, 25, "\(r.breakdown)")
        XCTAssertTrue(r.breakdown.contains { $0.factor == .wind && $0.points < 0 })
    }

    func testNightIsBetweenDawnAndDay() {
        let night = date(2026, 10, 18, 22, 0), noon = date(2026, 10, 18, 12, 0), dawn = date(2026, 10, 18, 5, 40)
        func s(_ at: Date) -> Int { ScoreEngine().score(ScoreInput(at: at, coordinate: hakodate, env: env(at: at, wind: 2, tideRate: 8))).score }
        XCTAssertGreaterThan(s(night), s(noon))
        XCTAssertGreaterThan(s(dawn), s(night))
    }

    func testForecastConfidence() {
        let at = date(2026, 10, 18, 5, 40)
        var e = env(at: at, wind: 2, tideRate: 12); e.isForecast = true
        XCTAssertEqual(ScoreEngine().score(ScoreInput(at: at, coordinate: hakodate, env: e)).confidence, .forecast)
        let bare = EnvSnapshot(at: at, coordinate: hakodate)
        XCTAssertEqual(ScoreEngine().score(ScoreInput(at: at, coordinate: hakodate, env: bare)).confidence, .noWeather)
    }

    func testLegacyInputStillWorks() {
        var e = EnvSnapshot(at: .now, coordinate: hakodate)
        e.windSpeedMS = 2; e.tideRateCmPerHour = 12; e.pressureTrend3hHPa = -1.5
        let r = ScoreEngine().score(.init(at: .now, env: e, minutesToNextTwilight: 30))
        XCTAssertGreaterThanOrEqual(r.score, 75)
    }

    // MARK: 自分データ

    func makeSession(day: Int, startHour: Int, hours: Int, catchesAtHours: [Int], wind: Double, tideRate: Double) -> Session {
        let spot = UUID()
        let start = date(2026, 10, day, startHour)
        let end = start.addingTimeInterval(Double(hours) * 3600)
        var s = Session(spotID: spot, startedAt: start, endedAt: end)
        s.snapshots = stride(from: 0, to: hours * 60, by: 30).map { m in env(at: start.addingTimeInterval(Double(m) * 60), wind: wind, tideRate: tideRate) }
        s.catches = catchesAtHours.map { h in
            Catch(sessionID: s.id, at: start.addingTimeInterval(Double(h) * 3600 + 600), coordinate: hakodate, species: "アイナメ", speciesConfidence: 0.9)
        }
        return s
    }

    func testPersonalModelLearnsFromCatchesAndBlanks() {
        // 朝マズメ・上げ潮で釣れ、昼・潮止まりでボウズ、を繰り返した履歴
        var sessions: [Session] = []
        for d in 1...10 {
            sessions.append(makeSession(day: d, startHour: 5, hours: 3, catchesAtHours: [0, 1], wind: 2, tideRate: 10))
            sessions.append(makeSession(day: d, startHour: 12, hours: 3, catchesAtHours: [], wind: 2, tideRate: 1))
        }
        let model = PersonalModel.learn(from: sessions, coordinateOf: { _ in self.hakodate }, timeZone: jst)
        XCTAssertEqual(model.total.catches, 20)
        XCTAssertEqual(model.total.hours, 60, accuracy: 0.01)
        XCTAssertGreaterThan(model.weight, 0.5)
        let dawn = ConditionBuckets(input: ScoreInput(at: date(2026, 10, 18, 5, 40), coordinate: hakodate, env: env(at: date(2026, 10, 18, 5, 40), wind: 2, tideRate: 10), timeZone: jst))
        let noon = ConditionBuckets(input: ScoreInput(at: date(2026, 10, 18, 12, 0), coordinate: hakodate, env: env(at: date(2026, 10, 18, 12, 0), wind: 2, tideRate: 1), timeZone: jst))
        XCTAssertGreaterThan(model.adjustment(for: dawn, species: nil).points, 0)
        XCTAssertLessThan(model.adjustment(for: noon, species: nil).points, 0)
        // 魚種別
        XCTAssertGreaterThan(model.adjustment(for: dawn, species: "アイナメ").points, 0)
        XCTAssertEqual(model.adjustment(for: dawn, species: "ホッケ").points, 0) // データなし → 0
    }

    func testAllBlankSessionsDoNotBreak() {
        let sessions = (1...8).map { makeSession(day: $0, startHour: 6, hours: 2, catchesAtHours: [], wind: 3, tideRate: 8) }
        let model = PersonalModel.learn(from: sessions, coordinateOf: { _ in self.hakodate }, timeZone: jst)
        XCTAssertEqual(model.total.catches, 0)
        let at = date(2026, 10, 18, 6, 30)
        let r = ScoreEngine(personal: model).score(ScoreInput(at: at, coordinate: hakodate, env: env(at: at, wind: 3, tideRate: 8), timeZone: jst))
        XCTAssertTrue((0...100).contains(r.score))
        XCTAssertTrue(r.breakdown.allSatisfy { $0.points.isFinite })
        let adj = model.adjustment(for: ConditionBuckets(input: ScoreInput(at: at, coordinate: hakodate, env: env(at: at, wind: 3, tideRate: 8), timeZone: jst)), species: nil)
        XCTAssertTrue(adj.points.isFinite)
        XCTAssertGreaterThanOrEqual(abs(adj.points), 0)
    }

    func testEmptyHistoryGivesNoAdjustment() {
        let model = PersonalModel.learn(from: [], coordinateOf: { _ in nil })
        XCTAssertEqual(model.weight, 0)
        let at = date(2026, 10, 18, 6, 0)
        XCTAssertEqual(model.adjustment(for: ConditionBuckets(input: ScoreInput(at: at, coordinate: hakodate, env: env(at: at, wind: 3, tideRate: 8))), species: nil).points, 0)
    }

    // MARK: 推移・イベント

    func testTimelineAndPeaks() {
        let from = date(2026, 10, 18, 0)
        let engine = ScoreEngine()
        let points = ScoreTimeline.compute(engine: engine, coordinate: hakodate, from: from, to: from.addingTimeInterval(86_400), stepMinutes: 15, timeZone: jst) { t in
            self.env(at: t, wind: 2, tideRate: 10)
        }
        XCTAssertEqual(points.count, 97)
        let peaks = ScoreTimeline.peaks(points, threshold: 75)
        XCTAssertGreaterThanOrEqual(peaks.count, 1)
        // 朝マズメの山がある
        XCTAssertTrue(peaks.contains { abs($0.maxAt.timeIntervalSince(self.date(2026, 10, 18, 5, 45))) < 2 * 3600 }, "\(peaks)")
    }

    func testOneDayTimelineUnder50ms() {
        let station = TideCatalog.bundled().nearest(to: hakodate)
        let tide = station.map { TideEngine(station: $0) }
        let from = date(2026, 10, 18, 0)
        let engine = ScoreEngine()
        func run() -> (count: Int, elapsed: TimeInterval) {
            let start = Date()
            let points = ScoreTimeline.compute(engine: engine, coordinate: hakodate, from: from, to: from.addingTimeInterval(86_400), stepMinutes: 15, timeZone: jst) { t in
                var e = self.env(at: t, wind: 3, tideRate: tide?.rate(at: t) ?? 0)
                e.tideLevelCm = tide?.level(at: t)
                return e
            }
            return (points.count, Date().timeIntervalSince(start))
        }
        // 初回はテーブルの初期化を含むので捨て、3 回のベストで判定する（CI の共有ランナーのぶれを吸収）
        _ = run()
        let results = (0..<3).map { _ in run() }
        XCTAssertEqual(results[0].count, 97)
        let best = results.map(\.elapsed).min() ?? 0
        XCTAssertLessThan(best, 0.05, "1 日分の推移に \(best * 1000) ms")
    }

    func testUpcomingEvents() {
        let from = date(2026, 10, 18, 4, 0)
        let extremes = [TideExtreme(kind: .high, at: date(2026, 10, 18, 9, 10), levelCm: 120), TideExtreme(kind: .low, at: date(2026, 10, 18, 15, 20), levelCm: 20)]
        let wind = [(date(2026, 10, 18, 6, 0), 3.0), (date(2026, 10, 18, 7, 0), 6.0), (date(2026, 10, 18, 12, 0), 4.0)]
        let events = ScoreEvents.upcoming(from: from, count: 3, coordinate: hakodate, timeZone: jst, tideExtremes: extremes, wind: wind)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].kind, .dawn)       // 5:2x 朝マズメ
        XCTAssertEqual(events[1].kind, .windUp)     // 7:00 風 3→6
        XCTAssertEqual(events[1].label, "風 3→6m/s")
        XCTAssertFalse(events[1].isPositive)
        XCTAssertEqual(events[2].kind, .highTide)   // 9:10 満潮
        XCTAssertTrue(events.map(\.at) == events.map(\.at).sorted())
    }
}
