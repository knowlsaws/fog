import Foundation
import XCTest
@testable import Core

final class ExportTests: XCTestCase {
    func testBundleRoundTrip() throws {
        let bundle = ExportBundle(exportedAt: SampleData.endedAt, spots: [SampleData.spot()], sessions: [SampleData.session()], points: [SampleData.point()],
                                  tackles: [SampleData.tackle()], rigs: [SampleData.rig()], species: Species.initialCatalog)
        let data = try bundle.jsonData()
        let back = try ExportBundle.from(json: data)
        XCTAssertEqual(back.sessions, bundle.sessions)
        XCTAssertEqual(back.spots, bundle.spots)
        XCTAssertEqual(back.rigs, bundle.rigs)
        XCTAssertEqual(back.version, 1)
    }

    func testCSVHasHeaderAndRows() {
        let sessions = [SampleData.session()]
        let csv = CSVExport.catches(sessions, spots: [SampleData.spot()])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("catch_id,session_id,spot,at"))
        XCTAssertTrue(lines[1].contains("函館港"))
        XCTAssertTrue(lines[1].contains("アイナメ"))
        XCTAssertTrue(lines[1].contains("38.0"))
        let s = CSVExport.sessions(sessions, spots: [SampleData.spot()])
        XCTAssertEqual(s.split(separator: "\n").count, 2)
        XCTAssertTrue(s.contains("上げ潮の朝マズメに1尾"))
        let snaps = CSVExport.snapshots(sessions)
        XCTAssertEqual(snaps.split(separator: "\n").count, 2)
        XCTAssertEqual(CSVExport.esc("a,b"), "\"a,b\"")
    }
}
