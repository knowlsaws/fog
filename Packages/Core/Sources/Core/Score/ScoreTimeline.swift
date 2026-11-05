import Foundation

/// 先の推移（ホームの上段グラフ）とピーク。データのある範囲まで出し、固定上限は設けない。
public struct ScorePoint: Hashable, Sendable {
    public var at: Date
    public var score: Int
    public var isForecast: Bool
    public var confidence: ScoreConfidence
    public init(at: Date, score: Int, isForecast: Bool, confidence: ScoreConfidence) {
        self.at = at; self.score = score; self.isForecast = isForecast; self.confidence = confidence
    }
}

public enum ScoreTimeline {
    /// `envAt` は各時刻の環境（App 側は予報キャッシュと端末計算で組み立てる。気象が切れた先は気象項目 nil）。
    public static func compute(engine: ScoreEngine, coordinate: Coordinate, from: Date, to: Date, stepMinutes: Int = 15,
                               species: String? = nil, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current,
                               envAt: (Date) -> EnvSnapshot) -> [ScorePoint] {
        guard to > from, stepMinutes > 0 else { return [] }
        var points: [ScorePoint] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var sunByDay: [Int: SunTimes] = [:]
        var t = from
        while t <= to {
            let env = envAt(t)
            let dayKey = Int((t.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: t))) / 86_400)
            let sun: SunTimes
            if let s = sunByDay[dayKey] { sun = s } else { sun = SunCalculator.times(on: t, at: coordinate, timeZone: timeZone); sunByDay[dayKey] = sun }
            var input = ScoreInput(at: t, coordinate: coordinate, env: env, species: species, timeZone: timeZone)
            input.precomputedSun = sun
            input.precomputedMonth = cal.component(.month, from: t)
            let r = engine.score(input)
            points.append(ScorePoint(at: t, score: r.score, isForecast: r.isForecast, confidence: r.confidence))
            t = t.addingTimeInterval(Double(stepMinutes) * 60)
        }
        return points
    }

    /// 連続した山（ピーク時間帯）。`threshold` 以上が続く区間と、その最高点。
    public struct Peak: Hashable, Sendable {
        public var start: Date
        public var end: Date
        public var maxScore: Int
        public var maxAt: Date
    }

    public static func peaks(_ points: [ScorePoint], threshold: Int = 70) -> [Peak] {
        var peaks: [Peak] = []
        var current: Peak?
        for p in points {
            if p.score >= threshold {
                if var c = current {
                    c.end = p.at
                    if p.score > c.maxScore { c.maxScore = p.score; c.maxAt = p.at }
                    current = c
                } else {
                    current = Peak(start: p.at, end: p.at, maxScore: p.score, maxAt: p.at)
                }
            } else if let c = current {
                peaks.append(c)
                current = nil
            }
        }
        if let c = current { peaks.append(c) }
        return peaks
    }

    /// 1 日の最良の時間帯：70 以上が続く区間のうち最高点のもの。無ければ最高点の前後 1 時間。
    public static func bestWindow(_ points: [ScorePoint]) -> Peak? {
        if let best = peaks(points, threshold: 70).max(by: { $0.maxScore < $1.maxScore }) { return best }
        guard let top = points.max(by: { $0.score < $1.score }) else { return nil }
        let start = points.first { $0.at >= top.at.addingTimeInterval(-3600) }?.at ?? top.at
        let end = points.last { $0.at <= top.at.addingTimeInterval(3600) }?.at ?? top.at
        return Peak(start: start, end: end, maxScore: top.score, maxAt: top.at)
    }

    /// 日ごとの最高点（キーはその日の 0 時）。
    public static func dailyMax(_ points: [ScorePoint], timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [Date: Int] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        var out: [Date: Int] = [:]
        for p in points {
            let day = cal.startOfDay(for: p.at)
            out[day] = max(out[day] ?? 0, p.score)
        }
        return out
    }
}
