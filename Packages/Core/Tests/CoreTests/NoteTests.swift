import XCTest
@testable import Core

final class NoteTests: XCTestCase {
    func testRoundTrip() throws {
        let note = Note(coordinate: Coordinate(latitude: 41.78, longitude: 140.72), text: "店の人：先週ホッケが好調", placeName: "鹿部漁港", source: .voice)
        let data = try JSONEncoder().encode(note)
        let back = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(back, note)
        XCTAssertEqual(back.source, .voice)
    }
}
