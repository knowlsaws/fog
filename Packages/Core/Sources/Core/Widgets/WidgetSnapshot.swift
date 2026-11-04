import Foundation

/// アプリがウィジェット用に書き出す「先の推移」のスナップショット（§8）。
/// ウィジェットは 15 分ごとのタイムラインをここから組み立てる。アプリが起動しなくても予報範囲の間は正しい値を出せる。
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Point: Codable, Hashable, Sendable {
        public var at: Date
        public var score: Int
        /// 潮が上げているか（nil は潮止まりか不明）
        public var tideRising: Bool?
        public var tideLevelCm: Double?
        public var airTemperatureC: Double?
        public var windSpeedMS: Double?
        public var windDirectionDeg: Double?
        public var conditionCode: String?
        public init(at: Date, score: Int, tideRising: Bool? = nil, tideLevelCm: Double? = nil,
                    airTemperatureC: Double? = nil, windSpeedMS: Double? = nil, windDirectionDeg: Double? = nil, conditionCode: String? = nil) {
            self.at = at; self.score = score; self.tideRising = tideRising; self.tideLevelCm = tideLevelCm
            self.airTemperatureC = airTemperatureC; self.windSpeedMS = windSpeedMS; self.windDirectionDeg = windDirectionDeg; self.conditionCode = conditionCode
        }
    }

    public struct Event: Codable, Hashable, Sendable {
        public var at: Date
        public var label: String
        /// `ScoreEvent.Kind` の rawValue（highTide / lowTide / dawn / dusk / windUp / windDown / sunrise / sunset）
        public var kind: String?
        public init(at: Date, label: String, kind: String? = nil) { self.at = at; self.label = label; self.kind = kind }
    }

    public var generatedAt: Date
    public var spotName: String
    /// 15 分刻み、時刻順
    public var points: [Point]
    /// 近いイベント（時刻順）
    public var events: [Event]
    public var isRecording: Bool
    public var tackle: TackleKind?

    public init(generatedAt: Date = .now, spotName: String, points: [Point], events: [Event], isRecording: Bool, tackle: TackleKind? = nil) {
        self.generatedAt = generatedAt
        self.spotName = spotName
        self.points = points.sorted { $0.at < $1.at }
        self.events = events.sorted { $0.at < $1.at }
        self.isRecording = isRecording
        self.tackle = tackle
    }

    /// `date` 時点の値（直前の点）。範囲外なら端の点。
    public func point(at date: Date) -> Point? {
        guard !points.isEmpty else { return nil }
        if let i = points.lastIndex(where: { $0.at <= date }) { return points[i] }
        return points.first
    }

    public func nextEvent(after date: Date) -> Event? {
        events.first { $0.at > date }
    }

    /// 次の満干・次のマズメ（種類で絞る）
    public func nextEvent(after date: Date, kinds: Set<String>) -> Event? {
        events.first { $0.at > date && $0.kind.map { kinds.contains($0) } == true }
    }

    /// `from` から `step` 刻みで `count` 個。ウィジェットのタイムライン用。
    public func timeline(from: Date, stepMinutes: Int = 15, count: Int = 96) -> [Point] {
        guard !points.isEmpty else { return [] }
        let step = TimeInterval(stepMinutes * 60)
        let last = points.last!.at
        var out: [Point] = []
        var t = from
        while out.count < count, t <= last {
            if var p = point(at: t) { p.at = t; out.append(p) }
            t += step
        }
        if out.isEmpty, let p = point(at: from) { out.append(Point(at: from, score: p.score, tideRising: p.tideRising, tideLevelCm: p.tideLevelCm)) }
        return out
    }

    /// 期間内の潮位の最小・最大（中ウィジェットの潮グラフの縦軸）
    public func tideRange(from: Date, to: Date) -> ClosedRange<Double>? {
        let levels = points.filter { $0.at >= from && $0.at <= to }.compactMap(\.tideLevelCm)
        guard let lo = levels.min(), let hi = levels.max() else { return nil }
        return lo...(hi > lo ? hi : lo + 1)
    }

    public func jsonData() throws -> Data { try FogJSON.encode(self) }
    public static func from(json: Data) throws -> WidgetSnapshot { try FogJSON.decode(WidgetSnapshot.self, from: json) }
}

/// 釣れ率ピーク通知（§8）：登録釣り場で今日のピークが `threshold` 以上になるとき、その 1 時間前に 1 回だけ。
public enum PeakNotificationPlanner {
    public struct Plan: Hashable, Sendable {
        public var fireAt: Date
        public var peakStart: Date
        public var maxScore: Int
        public var maxAt: Date
    }

    /// `now` 以降に鳴らせる今日のピーク通知。すでに通知時刻を過ぎていれば nil（鳴らさない）。
    public static func plan(points: [ScorePoint], now: Date, threshold: Int = 80, leadTime: TimeInterval = 3600,
                            timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> Plan? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let today = points.filter { $0.at >= dayStart && $0.at < dayEnd }
        let peaks = ScoreTimeline.peaks(today, threshold: threshold)
        guard let best = peaks.max(by: { $0.maxScore < $1.maxScore }) else { return nil }
        let fireAt = best.start.addingTimeInterval(-leadTime)
        guard fireAt > now else { return nil }
        return Plan(fireAt: fireAt, peakStart: best.start, maxScore: best.maxScore, maxAt: best.maxAt)
    }

    /// 「1 日 1 回」のキー（通知 ID と既送信の記録に使う）
    public static func dayKey(for date: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}
