import Foundation

/// 統計・相関（§5）。すべて保存データから毎回導出する（削除が即時反映される）。
public enum Analytics {
    // MARK: 釣り場別

    public struct SpotStats: Hashable, Sendable {
        public var sessions: Int
        public var catches: Int
        public var hours: Double
        public var catchesPerHour: Double
        public var blankRate: Double
        public var hookLosses: Int
        /// 針ロスト率（1 時間あたり）
        public var hookLossPerHour: Double
        /// 釣れたポイント（メッシュキー → 尾数）。ヒートマップの元
        public var catchHeatmap: [String: Int]
        /// 根掛かりの多いポイント（メッシュキー → 回数）
        public var hookLossHeatmap: [String: Int]
        public var lastSessionAt: Date?
        /// よく釣れる魚種（尾数順）
        public var topSpecies: [(species: String, count: Int)]

        public static func == (l: SpotStats, r: SpotStats) -> Bool {
            l.sessions == r.sessions && l.catches == r.catches && l.hours == r.hours && l.hookLosses == r.hookLosses
        }
        public func hash(into h: inout Hasher) { h.combine(sessions); h.combine(catches) }
    }

    public static func spotStats(sessions: [Session], meshSizeM: Double = Mesh.defaultSizeM) -> SpotStats {
        let finished = sessions
        let catches = finished.flatMap(\.catches)
        let hours = finished.reduce(0.0) { acc, s in acc + ((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt) / 3600) }
        let blanks = finished.filter(\.isBlank).count
        let losses = finished.flatMap(\.hookEvents).filter { $0.kind == .lost }
        var catchMap: [String: Int] = [:]
        for c in catches { catchMap[Mesh.key(for: c.coordinate, sizeM: meshSizeM), default: 0] += 1 }
        var lossMap: [String: Int] = [:]
        for e in losses { lossMap[Mesh.key(for: e.coordinate, sizeM: meshSizeM), default: 0] += 1 }
        var bySpecies: [String: Int] = [:]
        for c in catches { bySpecies[c.species, default: 0] += 1 }
        return SpotStats(
            sessions: finished.count,
            catches: catches.count,
            hours: hours,
            catchesPerHour: hours > 0 ? Double(catches.count) / hours : 0,
            blankRate: finished.isEmpty ? 0 : Double(blanks) / Double(finished.count),
            hookLosses: losses.count,
            hookLossPerHour: hours > 0 ? Double(losses.count) / hours : 0,
            catchHeatmap: catchMap,
            hookLossHeatmap: lossMap,
            lastSessionAt: finished.map(\.startedAt).max(),
            topSpecies: bySpecies.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map { (species: $0.key, count: $0.value) }
        )
    }

    /// 釣り場ごとの統計（spotID → stats）。
    public static func statsBySpot(sessions: [Session]) -> [UUID: SpotStats] {
        Dictionary(grouping: sessions, by: \.spotID).mapValues { spotStats(sessions: $0) }
    }

    // MARK: 条件分布

    /// 釣れた条件の分布（魚種別・釣り場別の「釣れやすい条件」）。各バケットの尾数。
    public struct ConditionDistribution: Hashable, Sendable {
        public var byLight: [String: Int]
        public var byTide: [String: Int]
        public var byTideName: [String: Int]
        public var byWind: [String: Int]
        public var byMonth: [Int: Int]
        /// 水温 2℃ 刻み（下端）→ 尾数
        public var bySeaTemp: [Int: Int]
        /// 気圧傾向：下降 / 安定 / 上昇
        public var byPressureTrend: [String: Int]
        public var total: Int

        public init() { byLight = [:]; byTide = [:]; byTideName = [:]; byWind = [:]; byMonth = [:]; bySeaTemp = [:]; byPressureTrend = [:]; total = 0 }

        /// 最も多いバケット（表示用の一言）
        public func top(_ dict: [String: Int]) -> String? { dict.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key }
    }

    public static func conditionDistribution(of catches: [Catch], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> ConditionDistribution {
        var d = ConditionDistribution()
        for c in catches {
            guard let env = c.env else { continue }
            let b = ConditionBuckets(input: ScoreInput(at: c.at, coordinate: c.coordinate, env: env, timeZone: timeZone))
            d.byLight[b.light.rawValue, default: 0] += 1
            d.byTide[b.tide.rawValue, default: 0] += 1
            if let n = b.tideName { d.byTideName[n, default: 0] += 1 }
            d.byWind[b.wind.rawValue, default: 0] += 1
            d.byMonth[b.month, default: 0] += 1
            if let sst = env.seaSurfaceTempC { d.bySeaTemp[Int((sst / 2).rounded(.down)) * 2, default: 0] += 1 }
            if let t = env.pressureTrend3hHPa { d.byPressureTrend[t <= -1 ? "下降" : (t >= 1 ? "上昇" : "安定"), default: 0] += 1 }
            d.total += 1
        }
        return d
    }

    // MARK: 魚種別

    public struct SpeciesStats: Hashable, Sendable {
        public var species: String
        public var count: Int
        public var maxLengthCm: Double?
        public var firstCaughtAt: Date?
        public var lastCaughtAt: Date?
        /// 釣れた釣り場（spotID → 尾数）
        public var bySpot: [UUID: Int]
        /// サイズ分布（5 cm 刻みの下端 → 尾数）
        public var sizeHistogram: [Int: Int]
        /// 最大サイズの推移（更新時刻, cm）
        public var maxLengthHistory: [(Date, Double)]
        public var conditions: ConditionDistribution

        public static func == (l: SpeciesStats, r: SpeciesStats) -> Bool { l.species == r.species && l.count == r.count && l.maxLengthCm == r.maxLengthCm }
        public func hash(into h: inout Hasher) { h.combine(species); h.combine(count) }

        /// 上位 3 釣り場
        public var topSpots: [(UUID, Int)] { Array(bySpot.sorted { $0.value > $1.value }.prefix(3)).map { ($0.key, $0.value) } }
    }

    public static func speciesStats(catches: [Catch], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [SpeciesStats] {
        Dictionary(grouping: catches, by: \.species).map { species, items in
            let sorted = items.sorted { $0.at < $1.at }
            var hist: [Int: Int] = [:]
            var history: [(Date, Double)] = []
            var best = -Double.infinity
            for c in sorted {
                if let l = c.lengthCm {
                    hist[Int((l / 5).rounded(.down)) * 5, default: 0] += 1
                    if l > best { best = l; history.append((c.at, l)) }
                }
            }
            return SpeciesStats(
                species: species,
                count: sorted.count,
                maxLengthCm: sorted.compactMap(\.lengthCm).max(),
                firstCaughtAt: sorted.first?.at,
                lastCaughtAt: sorted.last?.at,
                bySpot: [:],
                sizeHistogram: hist,
                maxLengthHistory: history,
                conditions: conditionDistribution(of: sorted, timeZone: timeZone)
            )
        }.sorted { $0.count > $1.count || ($0.count == $1.count && $0.species < $1.species) }
    }

    /// 釣行（spotID 付き）から魚種別統計を出す。釣れた釣り場も埋まる。
    public static func speciesStats(sessions: [Session], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [SpeciesStats] {
        let spotOf = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.spotID) })
        var stats = speciesStats(catches: sessions.flatMap(\.catches), timeZone: timeZone)
        for i in stats.indices {
            var bySpot: [UUID: Int] = [:]
            for c in sessions.flatMap(\.catches) where c.species == stats[i].species {
                if let spot = spotOf[c.sessionID] { bySpot[spot, default: 0] += 1 }
            }
            stats[i].bySpot = bySpot
        }
        return stats
    }

    // MARK: 時間帯 × 月

    public struct HourMonthCell: Hashable, Sendable {
        public var hour: Int
        public var month: Int
        public var catches: Int
        public var averageLengthCm: Double?
    }

    /// 時間帯（0〜23 時）× 月の釣果数と平均サイズ。釣果が無いセルは含めない。
    public static func hourMonthStats(catches: [Catch], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [HourMonthCell] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var cells: [String: (Int, [Double])] = [:]
        for c in catches {
            let h = cal.component(.hour, from: c.at), m = cal.component(.month, from: c.at)
            var cell = cells["\(h)-\(m)"] ?? (0, [])
            cell.0 += 1
            if let l = c.lengthCm { cell.1.append(l) }
            cells["\(h)-\(m)"] = cell
        }
        return cells.map { key, v in
            let parts = key.split(separator: "-").map { Int($0)! }
            return HourMonthCell(hour: parts[0], month: parts[1], catches: v.0, averageLengthCm: v.1.isEmpty ? nil : v.1.reduce(0, +) / Double(v.1.count))
        }.sorted { ($0.month, $0.hour) < ($1.month, $1.hour) }
    }

    /// 時間帯別の釣果数（ログ画面の分析カード 1 枚目）
    public static func catchesByHour(catches: [Catch], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [Int: Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [Int: Int] = [:]
        for c in catches { out[cal.component(.hour, from: c.at), default: 0] += 1 }
        return out
    }

    /// 月ごとの釣果推移（前回比・傾向）
    public static func catchesByMonth(catches: [Catch], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [(year: Int, month: Int, count: Int)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [String: (Int, Int, Int)] = [:]
        for c in catches {
            let y = cal.component(.year, from: c.at), m = cal.component(.month, from: c.at)
            var v = out["\(y)-\(m)"] ?? (y, m, 0)
            v.2 += 1
            out["\(y)-\(m)"] = v
        }
        return out.values.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { (year: $0.0, month: $0.1, count: $0.2) }
    }

    // MARK: タックル・リグ別

    public struct RigStats: Hashable, Sendable {
        public var rigID: UUID?
        public var catches: Int
        public var hookLosses: Int
    }

    public static func rigStats(sessions: [Session]) -> [RigStats] {
        var catches: [UUID?: Int] = [:]
        var losses: [UUID?: Int] = [:]
        for s in sessions {
            for c in s.catches { catches[c.rigID ?? s.rigID, default: 0] += 1 }
            for e in s.hookEvents where e.kind == .lost { losses[e.rigID ?? s.rigID, default: 0] += 1 }
        }
        let keys = Set(catches.keys).union(losses.keys)
        return keys.map { RigStats(rigID: $0, catches: catches[$0] ?? 0, hookLosses: losses[$0] ?? 0) }
            .sorted { $0.catches > $1.catches }
    }

    public static func catchesByTackle(sessions: [Session]) -> [TackleKind: Int] {
        var out: [TackleKind: Int] = [:]
        for s in sessions { for c in s.catches { if let k = c.tackle ?? s.tackle { out[k, default: 0] += 1 } } }
        return out
    }

    // MARK: 前回比

    public struct Comparison: Hashable, Sendable {
        public var catchesDelta: Int
        public var hoursDelta: Double
        public var windDeltaMS: Double?
        public var seaTempDeltaC: Double?
        public var pressureTrendDelta: Double?
        public var tideNameNow: String?
        public var tideNamePrevious: String?
    }

    /// 同じ釣り場の前回との条件差と結果差。前回が無ければ nil。
    public static func comparison(current: Session, previous: Session?) -> Comparison? {
        guard let previous else { return nil }
        func avg(_ s: Session, _ key: (EnvSnapshot) -> Double?) -> Double? {
            let v = s.snapshots.compactMap(key)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func delta(_ key: @escaping (EnvSnapshot) -> Double?) -> Double? {
            guard let a = avg(current, key), let b = avg(previous, key) else { return nil }
            return a - b
        }
        return Comparison(
            catchesDelta: current.catches.count - previous.catches.count,
            hoursDelta: ((current.duration ?? 0) - (previous.duration ?? 0)) / 3600,
            windDeltaMS: delta(\.windSpeedMS),
            seaTempDeltaC: delta(\.seaSurfaceTempC),
            pressureTrendDelta: delta(\.pressureTrend3hHPa),
            tideNameNow: current.snapshots.first?.tideName,
            tideNamePrevious: previous.snapshots.first?.tideName
        )
    }

    // MARK: 記録更新の判定（F-20）

    public struct RecordJudgement: Hashable, Sendable {
        public var isFirstSpecies: Bool
        public var isPersonalBest: Bool
        public var isSpotRecord: Bool
        public var previousBestCm: Double?
        public var hasAny: Bool { isFirstSpecies || isPersonalBest || isSpotRecord }
    }

    /// `new` を記録したとき、既存の釣果（`new` 自身を除く）と比べて初魚種・自己記録・釣り場記録か。
    /// 推定幅を考慮：新しい記録の下限（length − error）が既存の最大の上限（length + error）を超えたときだけ自己記録。
    public static func judge(new: Catch, newSpotID: UUID, existing: [(Catch, UUID)]) -> RecordJudgement {
        let others = existing.filter { $0.0.id != new.id }
        let same = others.filter { $0.0.species == new.species }
        let isFirst = same.isEmpty
        func upper(_ c: Catch) -> Double? { c.lengthCm.map { $0 + (c.lengthErrorCm ?? 0) } }
        let newLower = new.lengthCm.map { $0 - (new.lengthErrorCm ?? 0) }
        let bestAll = same.compactMap { upper($0.0) }.max()
        let bestSpot = same.filter { $0.1 == newSpotID }.compactMap { upper($0.0) }.max()
        var personal = false, spotRecord = false
        if let newLower {
            personal = !isFirst && (bestAll.map { newLower > $0 } ?? true)
            spotRecord = !isFirst && (bestSpot.map { newLower > $0 } ?? true) && !same.filter { $0.1 == newSpotID }.isEmpty
        }
        return RecordJudgement(isFirstSpecies: isFirst, isPersonalBest: personal, isSpotRecord: spotRecord,
                               previousBestCm: same.compactMap { $0.0.lengthCm }.max())
    }
}
