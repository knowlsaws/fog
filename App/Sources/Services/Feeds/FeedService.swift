import Foundation
import Core
import os

/// 登録 RSS の取得と保存（F-27）。原則 3 で許された外部通信のひとつ。
/// URL は設定（UserDefaults）、記事は App Group の JSON。取得はフィードごとに 1 時間に 1 回まで。
@MainActor
@Observable
final class FeedService {
    static let urlsKey = "fog.feeds.urls"
    static let maxItemsPerFeed = 50
    private(set) var items: [FeedItem] = []
    private(set) var feedTitles: [String: String] = [:]
    private(set) var lastError: String?
    private var gate = FetchGate(minimumInterval: 3600)
    private var refreshing = false
    private static let log = Logger(subsystem: "fog", category: "feeds")

    private var storeURL: URL { FogShared.containerURL.appendingPathComponent("feeds.json") }

    init() { load() }

    var urls: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.urlsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.urlsKey) }
    }

    func add(url: String) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, URL(string: u)?.scheme?.hasPrefix("http") == true, !urls.contains(u) else { return }
        urls.append(u)
        gate.release(u)
        Task { await refreshIfNeeded(force: true) }
    }

    func remove(url: String) {
        urls.removeAll { $0 == url }
        items.removeAll { $0.feedURL == url }
        feedTitles[url] = nil
        save()
    }

    /// 必要なら取得。圏外や失敗でも投げない（残っている記事で動く）
    func refreshIfNeeded(now: Date = .now, force: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        var changed = false
        for url in urls {
            guard force || gate.tryAcquire(url, now: now), let u = URL(string: url) else { continue }
            do {
                var req = URLRequest(url: u)
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let parsed = FeedParser.parse(data, feedURL: url, fetchedAt: now) else {
                    lastError = "読めない形式: \(url)"
                    continue
                }
                feedTitles[url] = parsed.title
                var merged = items.filter { $0.feedURL != url }
                let known = Dictionary(uniqueKeysWithValues: items.filter { $0.feedURL == url }.map { ($0.id, $0) })
                let fresh = parsed.items.map { i -> FeedItem in var i = i; if let k = known[i.id] { i.fetchedAt = k.fetchedAt }; return i }
                merged += Array(fresh.prefix(Self.maxItemsPerFeed))
                items = merged
                lastError = nil
                changed = true
            } catch {
                gate.release(url)
                lastError = error.localizedDescription
                Self.log.notice("feed fetch failed \(url, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if changed { save() }
    }

    /// 関連が強い順（魚種名・釣り場名）→ 新しい順
    func sorted(keywords: [String]) -> [FeedItem] { FeedRelevance.sorted(items, keywords: keywords) }

    /// ホームの 1 行：関連が強い記事か、無ければ最新
    func headline(keywords: [String]) -> FeedItem? { sorted(keywords: keywords).first }

    private struct Persisted: Codable { var items: [FeedItem]; var titles: [String: String]; var gate: FetchGate }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL), let p = try? FogJSON.decode(Persisted.self, from: data) else { return }
        items = p.items; feedTitles = p.titles; gate = p.gate
    }

    private func save() {
        guard let data = try? FogJSON.encode(Persisted(items: items, titles: feedTitles, gate: gate)) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
