import XCTest
@testable import Core

final class ModelsTests: XCTestCase {
    func testSessionRoundTripsThroughJSON() throws {
        let spot = Spot(name: "函館港", coordinate: .init(latitude: 41.78, longitude: 140.72))
        var session = Session(spotID: spot.id, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        session.catches.append(Catch(sessionID: session.id, at: session.startedAt.addingTimeInterval(1800),
                                     coordinate: spot.coordinate, species: "アイナメ", speciesConfidence: 0.92, lengthCm: 38))
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
    }
}

final class TideNameTests: XCTestCase {
    func testNewMoonIsSpringTide() {
        XCTAssertEqual(TideName.from(moonAge: 0.5), .spring)
        XCTAssertEqual(TideName.from(moonAge: 15.2), .spring)
    }
    func testNeapAroundQuarter() {
        XCTAssertEqual(TideName.from(moonAge: 7.5), .neap)
    }
}

final class MoonPhaseTests: XCTestCase {
    func testAgeIsWithinSynodicMonth() {
        let age = MoonPhase.age(at: Date(timeIntervalSince1970: 1_762_200_000))
        XCTAssertGreaterThanOrEqual(age, 0)
        XCTAssertLessThan(age, MoonPhase.synodicMonth)
    }
}

final class ScoreEngineTests: XCTestCase {
    func testDawnMovingTideLightWindScoresHigh() {
        var env = EnvSnapshot(at: .now, coordinate: .init(latitude: 41.78, longitude: 140.72))
        env.windSpeedMS = 2; env.tideRateCmPerHour = 12; env.pressureTrend3hHPa = -1.5
        let r = ScoreEngine().score(.init(at: .now, env: env, minutesToNextTwilight: 30))
        XCTAssertGreaterThanOrEqual(r.score, 75)
    }
    func testStrongWindSlackTideScoresLow() {
        var env = EnvSnapshot(at: .now, coordinate: .init(latitude: 41.78, longitude: 140.72))
        env.windSpeedMS = 10; env.tideRateCmPerHour = 1
        let r = ScoreEngine().score(.init(at: .now, env: env, minutesToNextTwilight: 300))
        XCTAssertLessThanOrEqual(r.score, 30)
    }
}

final class AnalyticsTests: XCTestCase {
    func testSpotStats() {
        let spot = UUID()
        let s1 = Session(spotID: spot, startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 7200),
                         catches: [Catch(sessionID: UUID(), at: .now, coordinate: .init(latitude: 0, longitude: 0), species: "ソイ", speciesConfidence: 0.8)])
        let s2 = Session(spotID: spot, startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 3600))
        let stats = Analytics.spotStats(sessions: [s1, s2])
        XCTAssertEqual(stats.sessions, 2)
        XCTAssertEqual(stats.catches, 1)
        XCTAssertEqual(stats.blankRate, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.catchesPerHour, 1.0 / 3.0, accuracy: 0.001)
    }
}
