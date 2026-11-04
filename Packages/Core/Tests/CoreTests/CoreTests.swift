import XCTest
@testable import Core

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
