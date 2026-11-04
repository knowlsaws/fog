import Foundation

/// 自分の釣果データによるスコア重みの学習（F-17）。
/// 条件バケットごとの「1 時間あたり釣果数」を全体と比べ、釣行時間が蓄積されるほど重みを上げる。
/// ボウズの釣行も時間として数えるので、釣れない条件は下がる。
public struct PersonalModel: Hashable, Sendable {
    public struct Stat: Hashable, Sendable {
        public var hours: Double
        public var catches: Int
        public init(hours: Double = 0, catches: Int = 0) { self.hours = hours; self.catches = catches }
        /// 平滑化した時間あたり釣果数
        public var rate: Double { (Double(catches) + 0.5) / (hours + 1) }
    }

    public var total: Stat
    public var byLight: [String: Stat]
    public var byTide: [String: Stat]
    public var byWind: [String: Stat]
    public var byTideName: [String: Stat]
    public var byMonth: [Int: Stat]
    /// 魚種ごと（魚種別スコア用）
    public var bySpecies: [String: PersonalModel]

    public init() {
        total = Stat(); byLight = [:]; byTide = [:]; byWind = [:]; byTideName = [:]; byMonth = [:]; bySpecies = [:]
    }

    /// 釣行から学習する。釣行中の各スナップショットを 30 分（次のスナップショットまで）の滞在として数え、その時刻の釣果を数える。
    public static func learn(from sessions: [Session], coordinateOf: (Session) -> Coordinate?, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> PersonalModel {
        var model = PersonalModel()
        for session in sessions {
            guard let end = session.endedAt, let coordinate = coordinateOf(session) ?? session.snapshots.first?.coordinate else { continue }
            let snapshots = session.snapshots.sorted { $0.at < $1.at }
            let slots: [(EnvSnapshot, Date, Date)]
            if snapshots.isEmpty {
                // スナップショットが無い釣行は条件なし（全体の時間だけ）
                slots = []
            } else {
                slots = snapshots.enumerated().map { i, s in
                    let next = i + 1 < snapshots.count ? snapshots[i + 1].at : end
                    return (s, s.at, min(next, end))
                }
            }
            let hoursTotal = end.timeIntervalSince(session.startedAt) / 3600
            model.total.hours += hoursTotal
            model.total.catches += session.catches.count
            for (snapshot, from, to) in slots {
                let hours = max(0, to.timeIntervalSince(from)) / 3600
                let catches = session.catches.filter { $0.at >= from && $0.at < to }
                let buckets = ConditionBuckets(input: ScoreInput(at: from, coordinate: coordinate, env: snapshot, timeZone: timeZone))
                model.add(buckets: buckets, hours: hours, catches: catches.count)
                for c in catches {
                    var sp = model.bySpecies[c.species] ?? PersonalModel()
                    sp.add(buckets: buckets, hours: 0, catches: 1)
                    model.bySpecies[c.species] = sp
                }
                for name in Set(session.catches.map(\.species)) {
                    var sp = model.bySpecies[name] ?? PersonalModel()
                    sp.add(buckets: buckets, hours: hours, catches: 0)
                    sp.total.hours += 0
                    model.bySpecies[name] = sp
                }
            }
            for name in Set(session.catches.map(\.species)) {
                model.bySpecies[name, default: PersonalModel()].total.hours += hoursTotal
                model.bySpecies[name, default: PersonalModel()].total.catches += session.catches.filter { $0.species == name }.count
            }
        }
        return model
    }

    mutating func add(buckets: ConditionBuckets, hours: Double, catches: Int) {
        func bump(_ dict: inout [String: Stat], _ key: String) {
            var s = dict[key] ?? Stat()
            s.hours += hours; s.catches += catches
            dict[key] = s
        }
        bump(&byLight, buckets.light.rawValue)
        bump(&byTide, buckets.tide.rawValue)
        bump(&byWind, buckets.wind.rawValue)
        if let n = buckets.tideName { bump(&byTideName, n) }
        var m = byMonth[buckets.month] ?? Stat()
        m.hours += hours; m.catches += catches
        byMonth[buckets.month] = m
    }

    /// 釣行時間が増えるほど 0 → 1 に近づく（40 時間で 0.5、ボウズも含む）。
    public var weight: Double { total.hours / (total.hours + 40) }

    /// バケットごとの対数比を合計し、重みを掛けて ±20 点に収める。
    public func adjustment(for buckets: ConditionBuckets, species: String?) -> (points: Double, detail: String) {
        // 魚種別は自分がその魚種を釣った実績だけで判断する（未釣果の魚種は補正なし）
        let model: PersonalModel
        if let species {
            guard let sp = bySpecies[species] else { return (0, "データ不足") }
            model = sp
        } else {
            model = self
        }
        guard model.total.hours >= 2 else { return (0, "データ不足") }
        let base = model.total.rate
        func term(_ stat: Stat?) -> Double {
            guard let stat, stat.hours >= 1 else { return 0 }
            let ratio = log((stat.rate + 1e-6) / (base + 1e-6))
            let shrink = stat.hours / (stat.hours + 5)
            return max(-8, min(8, 8 * ratio)) * shrink
        }
        var sum = 0.0
        sum += term(model.byLight[buckets.light.rawValue])
        sum += term(model.byTide[buckets.tide.rawValue])
        sum += term(model.byWind[buckets.wind.rawValue])
        if let n = buckets.tideName { sum += term(model.byTideName[n]) }
        sum += term(model.byMonth[buckets.month])
        let points = (max(-20, min(20, sum)) * model.weight).rounded()
        let detail = "実績 \(Int(model.total.hours.rounded())) 時間・\(model.total.catches) 尾"
        return (points, detail)
    }
}
