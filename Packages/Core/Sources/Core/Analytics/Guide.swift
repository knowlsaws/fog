import Foundation

/// 図鑑（§5「図鑑の自動更新」）。自分が釣った魚種だけで構成し、初釣果で自動追加される。
public struct GuideEntry: Hashable, Sendable {
    public var species: String
    public var count: Int
    public var maxLengthCm: Double?
    public var firstCaughtAt: Date
    public var lastCaughtAt: Date
    /// ベストショット（最大サイズの釣果。サイズ未計測なら最新）
    public var bestCatchID: UUID
    public var photoLocalIdentifier: String?
    /// 釣れた釣り場（尾数順 上位 3）
    public var topSpots: [(spotID: UUID, count: Int)]
    /// 釣れやすい条件（分析から自動生成）
    public var conditions: Analytics.ConditionDistribution
    /// 直近 1 週間に記録更新（初釣果・自己記録）があった
    public var recentlyUpdated: Bool

    public static func == (l: GuideEntry, r: GuideEntry) -> Bool { l.species == r.species && l.count == r.count && l.maxLengthCm == r.maxLengthCm }
    public func hash(into h: inout Hasher) { h.combine(species) }

    public enum Sort: String, CaseIterable, Sendable { case maxLength, recent, count }
}

public enum Guide {
    public static func entries(sessions: [Session], now: Date = .now, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [GuideEntry] {
        let stats = Analytics.speciesStats(sessions: sessions, timeZone: timeZone)
        let allCatches = sessions.flatMap(\.catches)
        return stats.compactMap { s -> GuideEntry? in
            let items = allCatches.filter { $0.species == s.species }.sorted { $0.at < $1.at }
            guard let first = items.first, let last = items.last else { return nil }
            let best = items.filter { $0.lengthCm != nil }.max { ($0.lengthCm ?? 0) < ($1.lengthCm ?? 0) } ?? last
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            let recently = first.at >= weekAgo || (s.maxLengthHistory.last.map { $0.0 >= weekAgo } ?? false)
            return GuideEntry(
                species: s.species, count: s.count, maxLengthCm: s.maxLengthCm,
                firstCaughtAt: first.at, lastCaughtAt: last.at,
                bestCatchID: best.id, photoLocalIdentifier: best.photoLocalIdentifier ?? items.reversed().compactMap(\.photoLocalIdentifier).first,
                topSpots: s.topSpots.map { (spotID: $0.0, count: $0.1) },
                conditions: s.conditions,
                recentlyUpdated: recently
            )
        }
    }

    public static func sorted(_ entries: [GuideEntry], by sort: GuideEntry.Sort) -> [GuideEntry] {
        switch sort {
        case .maxLength: return entries.sorted { ($0.maxLengthCm ?? -1) > ($1.maxLengthCm ?? -1) }
        case .recent: return entries.sorted { $0.lastCaughtAt > $1.lastCaughtAt }
        case .count: return entries.sorted { $0.count > $1.count }
        }
    }
}
