import Foundation

/// RSS の無いサイト向け：ページのリンク一覧を記事として読む（F-45）。
/// 同じサイト内のリンクのうち「記事らしいもの」（文字が 6 文字以上、画像やナビではない、任意の条件を含む）を残す。
/// 日付は URL から拾い（2024-05-24 / 2024/05/24 / 20240524 / rep2024-05-24）、無ければ nil。通信は App 側。
public enum HTMLFeed {
    /// `<link rel="alternate" type="application/rss+xml|atom+xml" href="…">` を拾う（RSS の自動探索）
    public static func discoverFeedURLs(html: String, baseURL: URL) -> [URL] {
        var out: [URL] = []
        for m in matches(in: html, pattern: "<link[^>]+>") {
            let tag = m.lowercased()
            guard tag.contains("alternate"), tag.contains("rss") || tag.contains("atom") else { continue }
            guard let href = attribute("href", in: m), let u = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            if !out.contains(u) { out.append(u) }
        }
        return out
    }

    static let navWords = ["トップ", "ホーム", "会社", "お問い合わせ", "お問合せ", "問い合わせ", "プライバシー", "サイトマップ", "ログイン", "カート", "採用", "アクセス", "店舗案内",
                           "利用規約", "特定商取引", "home", "contact", "privacy", "login", "cart", "sitemap", "about", "category", "tag", "page/", "feed", "wp-login"]

    /// `html` のリンクを記事にする。`pathFilter` があれば URL にそれを含むものだけ
    public static func items(html: String, baseURL: URL, feedURL: String, feedTitle: String?, pathFilter: String?, fetchedAt: Date = .now, limit: Int = 60) -> [FeedItem] {
        let title = feedTitle ?? pageTitle(html: html) ?? baseURL.host ?? feedURL
        var out: [FeedItem] = []
        var seen = Set<String>()
        let host = baseURL.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        for m in matches(in: html, pattern: "<a\\b[^>]*href=[\"']([^\"'#]+)[\"'][^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            guard let href = attribute("href", in: m), let url = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: baseURL)?.absoluteURL else { continue }
            guard let h = url.host?.replacingOccurrences(of: "www.", with: ""), h == host else { continue }
            let path = url.path.lowercased()
            if ["jpg", "jpeg", "png", "gif", "pdf", "zip", "mp4"].contains(url.pathExtension.lowercased()) { continue }
            if let f = pathFilter, !f.isEmpty, !url.absoluteString.contains(f) { continue }
            let inner = innerText(m)
            let text = FeedParser.plainText(inner, limit: 120)
            guard text.count >= 6 else { continue }
            let lower = text.lowercased()
            if navWords.contains(where: { lower.contains($0.lowercased()) || path.contains($0.lowercased()) }) && (pathFilter ?? "").isEmpty { continue }
            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(FeedItem(id: key, feedURL: feedURL, feedTitle: title, title: text, link: key, summary: nil, publishedAt: date(in: key), fetchedAt: fetchedAt))
            if out.count >= limit { break }
        }
        return out
    }

    /// URL に含まれる日付（2024-05-24 / 2024/05/24 / 20240524 / 2024-5-4）。日本時間の 0 時
    public static func date(in urlString: String) -> Date? {
        let patterns = ["(20[0-9]{2})[-/_]([01]?[0-9])[-/_]([0-3]?[0-9])", "(20[0-9]{2})([01][0-9])([0-3][0-9])"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p), let m = re.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) else { continue }
            func g(_ i: Int) -> Int? { Range(m.range(at: i), in: urlString).flatMap { Int(urlString[$0]) } }
            guard let y = g(1), let mo = g(2), let d = g(3), (1...12).contains(mo), (1...31).contains(d) else { continue }
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
            if let date = cal.date(from: DateComponents(year: y, month: mo, day: d)) { return date }
        }
        return nil
    }

    static func pageTitle(html: String) -> String? {
        guard let m = matches(in: html, pattern: "<title[^>]*>(.*?)</title>", options: [.dotMatchesLineSeparators, .caseInsensitive]).first else { return nil }
        let t = FeedParser.plainText(innerText(m), limit: 60)
        return t.isEmpty ? nil : t
    }

    static func matches(in text: String, pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)), let r = Range(m.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }

    /// `<a …>内側</a>` の内側
    static func innerText(_ element: String) -> String {
        guard let open = element.range(of: ">"), let close = element.range(of: "</", options: .backwards) else { return element }
        return String(element[open.upperBound..<close.lowerBound])
    }
}
