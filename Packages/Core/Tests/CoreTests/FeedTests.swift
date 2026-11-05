import XCTest
@testable import Core

final class FeedTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testParseRSS() throws {
        let r = FeedParser.parse(try fixture("feed_rss"), feedURL: "https://example.com/rss")!
        XCTAssertEqual(r.title, "函館釣り情報")
        XCTAssertEqual(r.items.count, 2)
        let a = r.items[0]
        XCTAssertEqual(a.title, "函館港でアイナメ好調")
        XCTAssertEqual(a.link, "https://example.com/a1")
        XCTAssertEqual(a.id, "https://example.com/a1")
        XCTAssertEqual(a.feedTitle, "函館釣り情報")
        XCTAssertEqual(a.summary, "朝マズメに アイナメ が連発。40cm超えも。")
        XCTAssertEqual(a.publishedAt, ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z"))
        XCTAssertEqual(r.items[1].summary, "投げ釣りでカレイ。")
    }

    func testParseAtom() throws {
        let r = FeedParser.parse(try fixture("feed_atom"), feedURL: "https://example.com/atom")!
        XCTAssertEqual(r.title, "釣具店ブログ")
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].link, "https://example.com/b1")
        XCTAssertEqual(r.items[0].title, "ソイの入荷情報とおすすめリグ")
        XCTAssertEqual(r.items[0].publishedAt, ISO8601DateFormatter().date(from: "2026-11-05T01:00:00Z"))
    }

    func testInvalidReturnsNil() {
        XCTAssertNil(FeedParser.parse(Data("not xml".utf8), feedURL: "x"))
    }

    func testRelevanceSorting() throws {
        let rss = FeedParser.parse(try fixture("feed_rss"), feedURL: "r")!.items
        let atom = FeedParser.parse(try fixture("feed_atom"), feedURL: "a")!.items
        let sorted = FeedRelevance.sorted(atom + rss, keywords: ["アイナメ", "函館港"])
        XCTAssertEqual(sorted.first?.title, "函館港でアイナメ好調")
        XCTAssertEqual(FeedRelevance.matches(sorted[0], keywords: ["アイナメ", "函館港", "ソイ"]), ["アイナメ", "函館港"])
        // 関連が無いものは新しい順
        XCTAssertEqual(sorted[1].title, "ソイの入荷情報とおすすめリグ")
    }

    func testPlainText() {
        XCTAssertEqual(FeedParser.plainText("<p>a&amp;b</p>  <br/>c"), "a&b c")
        XCTAssertEqual(FeedParser.plainText(String(repeating: "あ", count: 300), limit: 10).count, 11)
    }

    func testInventoryConsume() {
        let rig = UUID()
        let items = [InventoryItem(name: "14g", kind: .sinker, count: 4, lowThreshold: 3, rigID: rig),
                     InventoryItem(name: "#1/0", kind: .hook, count: 10, lowThreshold: 3, rigID: rig),
                     InventoryItem(name: "ワーム", kind: .worm, count: 2, lowThreshold: 3, rigID: rig),
                     InventoryItem(name: "別のリグ", kind: .sinker, count: 1, lowThreshold: 3, rigID: UUID())]
        let r = Inventory.consumeHookLost(items, rigID: rig)
        XCTAssertEqual(r.items.map(\.count), [3, 9, 2, 1])
        XCTAssertEqual(r.nowLow.map(\.name), ["14g"])
        let none = Inventory.consumeHookLost(items, rigID: nil)
        XCTAssertEqual(none.items, items)
        // 0 より下には減らない
        let zero = Inventory.consumeHookLost([InventoryItem(name: "x", kind: .hook, count: 0, rigID: rig)], rigID: rig)
        XCTAssertEqual(zero.items[0].count, 0)
    }

    func testAccuracySplit() {
        let start = Date(timeIntervalSince1970: 1_762_300_000)
        let pts = (0..<9).map { i in ScorePoint(at: start.addingTimeInterval(Double(i) * 900), score: i < 4 ? 80 : 40, isForecast: false, confidence: .observed) }
        let a = SessionReview.split(points: pts, catchTimes: [start.addingTimeInterval(600), start.addingTimeInterval(5000)], from: start, to: start.addingTimeInterval(2 * 3600))
        XCTAssertEqual(a.highHours, 1.0, accuracy: 0.001)
        XCTAssertEqual(a.lowHours, 1.0, accuracy: 0.001)
        XCTAssertEqual(a.catchesHigh, 1)
        XCTAssertEqual(a.catchesLow, 1)
        let total = SessionReview.aggregate([a, a])
        XCTAssertEqual(total.sessions, 2)
        XCTAssertEqual(total.catchesPerHourHigh!, 1.0, accuracy: 0.001)
        XCTAssertEqual(total.ratio!, 1.0, accuracy: 0.001)
    }

    func testSnapshotSnagZoneDefaultsNil() throws {
        let s = WidgetSnapshot(spotName: "x", points: [], events: [], isRecording: false)
        let d = try WidgetSnapshot.from(json: try s.jsonData())
        XCTAssertNil(d.isSnagZone)
    }
}
