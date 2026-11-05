import XCTest
@testable import Core

final class HTMLFeedTests: XCTestCase {
    let html = """
    <html><head><title>フィッシングショップ・インパクト</title>
    <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml">
    </head><body>
    <a href="/">トップ</a> <a href="/company.html">会社案内</a>
    <a href="/report/report2024/rep2024-07-28.html"><img src="a.jpg">函館港 サバゲーに行こう！</a>
    <a href="report/report2024/rep2024-05-24.html">函館港ヤリイカエギング！</a>
    <a href="https://www.fs-impact.com/report/report2023/rep2023-04-05b.html">函館港アブラコ（アイナメ）釣行！</a>
    <a href="https://example.com/other">他のサイトの長いリンク</a>
    <a href="/photo/big.jpg">写真です写真です</a>
    <a href="/report/report2024/rep2024-05-24.html">函館港ヤリイカエギング！（重複）</a>
    <a href="/news/2026-11-01">短い</a>
    </body></html>
    """
    let base = URL(string: "https://www.fs-impact.com/")!

    func testDiscover() {
        let urls = HTMLFeed.discoverFeedURLs(html: html, baseURL: base)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://www.fs-impact.com/feed.xml"])
    }

    func testItems() {
        let items = HTMLFeed.items(html: html, baseURL: base, feedURL: "https://www.fs-impact.com/", feedTitle: nil, pathFilter: nil)
        XCTAssertEqual(items.map(\.title), ["函館港 サバゲーに行こう！", "函館港ヤリイカエギング！", "函館港アブラコ（アイナメ）釣行！"])
        XCTAssertEqual(items[0].link, "https://www.fs-impact.com/report/report2024/rep2024-07-28.html")
        XCTAssertEqual(items[0].feedTitle, "フィッシングショップ・インパクト")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(items[0].publishedAt, cal.date(from: DateComponents(year: 2024, month: 7, day: 28)))
        XCTAssertEqual(items[2].publishedAt, cal.date(from: DateComponents(year: 2023, month: 4, day: 5)))
        // 条件で絞る
        let filtered = HTMLFeed.items(html: html, baseURL: base, feedURL: "f", feedTitle: "x", pathFilter: "report2023")
        XCTAssertEqual(filtered.count, 1)
    }

    func testDateInURL() {
        XCTAssertNotNil(HTMLFeed.date(in: "https://x/2026/11/04/post"))
        XCTAssertNotNil(HTMLFeed.date(in: "https://x/p20261104.html"))
        XCTAssertNil(HTMLFeed.date(in: "https://x/p/12345"))
        XCTAssertNil(HTMLFeed.date(in: "https://x/2026-13-40"))
    }
}
