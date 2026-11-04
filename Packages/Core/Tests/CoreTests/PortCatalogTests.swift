import XCTest
@testable import Core

final class PortCatalogTests: XCTestCase {
    func testBundledCatalogDecodesAndFilters() {
        let catalog = PortCatalog.bundled()
        // CI の port-data が埋めるまでは空でもよい。入っていれば函館周辺に漁港がある
        if !catalog.isEmpty {
            XCTAssertGreaterThan(catalog.ports.count, 500)
            let near = catalog.ports(latitude: 41.6...42.2, longitude: 140.4...141.2)
            XCTAssertFalse(near.isEmpty, "函館周辺の港が無い")
            XCTAssertTrue(near.contains { $0.name.contains("漁港") }, "\(near.prefix(5))")
        }
        let sample = PortCatalog(ports: [Port(name: "鹿部漁港", lat: 42.03, lon: 140.81, kind: .fishing), Port(name: "函館港", lat: 41.78, lon: 140.72, kind: .harbor)])
        XCTAssertEqual(sample.ports(latitude: 42...42.1, longitude: 140.7...140.9).map(\.name), ["鹿部漁港"])
        XCTAssertEqual(sample.nearest(to: Coordinate(latitude: 41.79, longitude: 140.72), within: 5000)?.name, "函館港")
        XCTAssertNil(sample.nearest(to: Coordinate(latitude: 43.0, longitude: 141.3), within: 5000))
    }
}
