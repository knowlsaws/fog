import Foundation
import XCTest
@testable import Core

/// L4 受け入れ条件: 位置のシミュレーション（GPX）で開始・終了・ランガンが期待通りになる。通過だけでは開始しない。
final class SessionDetectionTests: XCTestCase {
    let port = Coordinate(latitude: 41.7822, longitude: 140.7192)

    func fixes(_ name: String) throws -> [LocationFix] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "gpx", subdirectory: "Fixtures"))
        let fixes = GPX.parse(try Data(contentsOf: url))
        XCTAssertFalse(fixes.isEmpty)
        return fixes
    }

    /// 港から 300 m 以内を海岸近傍とみなす簡易コンテキスト
    func context(for fix: LocationFix, spots: [Coordinate] = []) -> SessionDetector.Context {
        let shore = [port, Coordinate(latitude: 41.7700, longitude: 140.7400)].contains { Geo.distanceMeters($0, fix.coordinate) < 300 }
        return SessionDetector.Context(registeredSpotID: nil, nearShore: shore)
    }

    func run(_ name: String, settings: DetectionSettings = .default) throws -> [SessionDetector.Event] {
        var detector = SessionDetector(settings: settings)
        var events: [SessionDetector.Event] = []
        for fix in try fixes(name) {
            events += detector.handle(fix, context: context(for: fix))
        }
        return events
    }

    func testSimpleSessionStartsAfterDwellAndEndsWhenDriving() throws {
        let events = try run("gpx_session_simple")
        let starts = events.compactMap { e -> Date? in if case .start(let at, _, _) = e { return at }; return nil }
        let ends = events.compactMap { e -> Date? in if case .end(let at) = e { return at }; return nil }
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(ends.count, 1)
        // 開始は到着時刻（10 分後）、終了は走り出した時刻（50 分後）前後
        let t0 = Date(timeIntervalSince1970: 1_792_267_200)
        XCTAssertEqual(starts[0].timeIntervalSince(t0), 600, accuracy: 120)
        XCTAssertEqual(ends[0].timeIntervalSince(t0), 3000, accuracy: 240)
        let tracks = events.filter { if case .track = $0 { return true }; return false }
        XCTAssertGreaterThanOrEqual(tracks.count, 1)
    }

    func testPassingByDoesNotStart() throws {
        let events = try run("gpx_pass_by")
        XCTAssertTrue(events.isEmpty, "\(events)")
    }

    func testShortStopDoesNotStart() throws {
        let events = try run("gpx_short_stop")
        XCTAssertTrue(events.isEmpty, "\(events)")
        // 高感度（5 分）なら開始する
        let high = try run("gpx_short_stop", settings: .forSensitivity(.high))
        XCTAssertTrue(high.contains { if case .start = $0 { return true }; return false })
    }

    func testRunAndGunMergesIntoOneSession() throws {
        let events = try run("gpx_run_and_gun")
        let starts = events.filter { if case .start = $0 { return true }; return false }
        let resumes = events.filter { if case .resume = $0 { return true }; return false }
        let ends = events.filter { if case .end = $0 { return true }; return false }
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(resumes.count, 1)
        XCTAssertEqual(ends.count, 2) // A を離れたときと最後
    }

    func testRegisteredSpotStartsWithoutShoreInfo() {
        var detector = SessionDetector(settings: .forSensitivity(.high))
        let spotID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_792_267_200)
        var events: [SessionDetector.Event] = []
        for i in 0..<8 {
            let fix = LocationFix(at: t0.addingTimeInterval(Double(i) * 60), coordinate: port, horizontalAccuracyM: 15, speedMS: 0)
            events += detector.handle(fix, context: .init(registeredSpotID: spotID, nearShore: nil))
        }
        guard case .start(_, _, let id)? = events.first else { return XCTFail("start expected: \(events)") }
        XCTAssertEqual(id, spotID)
    }

    func testBadAccuracyIgnored() {
        var detector = SessionDetector(settings: .forSensitivity(.high))
        let t0 = Date(timeIntervalSince1970: 1_792_267_200)
        for i in 0..<10 {
            let fix = LocationFix(at: t0.addingTimeInterval(Double(i) * 60), coordinate: port, horizontalAccuracyM: 500, speedMS: 0)
            XCTAssertTrue(detector.handle(fix, context: .init(nearShore: true)).isEmpty)
        }
        XCTAssertEqual(detector.state, .idle)
    }

    func testMeshKeyAndCenter() {
        let key = Mesh.key(for: port)
        XCTAssertTrue(key.hasPrefix("30m:"))
        XCTAssertEqual(key, Mesh.key(for: Coordinate(latitude: port.latitude + 0.00005, longitude: port.longitude + 0.00005)))
        XCTAssertNotEqual(key, Mesh.key(for: Coordinate(latitude: port.latitude + 0.001, longitude: port.longitude)))
        let center = Mesh.center(for: port)
        XCTAssertLessThan(Geo.distanceMeters(center, port), 25)
    }

    func testSettingsBySensitivity() {
        XCTAssertLessThan(DetectionSettings.forSensitivity(.high).dwellToStart, DetectionSettings.forSensitivity(.medium).dwellToStart)
        XCTAssertLessThan(DetectionSettings.forSensitivity(.medium).dwellToStart, DetectionSettings.forSensitivity(.low).dwellToStart)
    }
}
