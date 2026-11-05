import Foundation

/// 前日の夜に送る「明日のベストタイム」通知（F-28）。
/// 明日の推移から最良の時間帯を 1 つ選び、マズメ・満干・気温を添えた 1 通の本文を作る。
public enum DailyBriefPlanner {
    public struct Brief: Hashable, Sendable {
        /// 通知を鳴らす時刻（今日の `fireHour` 時）
        public var fireAt: Date
        public var windowStart: Date
        public var windowEnd: Date
        public var maxScore: Int
        public var title: String
        public var body: String
    }

    /// `points` は明日 1 日分（15 分刻み）。`now` が通知時刻を過ぎていれば nil。
    /// - Parameters:
    ///   - extremes: 明日の満干
    ///   - sun: 明日の日の出入
    ///   - airTemperatureC: 明日の時間帯の気温（任意）
    ///   - fireHour: 今日の何時に鳴らすか（既定 20 時）
    public static func plan(points: [ScorePoint], extremes: [TideExtreme], sun: SunTimes?, airTemperatureC: Double?,
                            now: Date, fireHour: Int = 20, spotName: String,
                            timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> Brief? {
        guard let window = ScoreTimeline.bestWindow(points) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        guard let fireAt = cal.date(bySettingHour: fireHour, minute: 0, second: 0, of: now), fireAt > now else { return nil }
        let f = DateFormatter(); f.timeZone = timeZone; f.dateFormat = "H:mm"
        let title = "\(spotName) 明日のベスト \(f.string(from: window.start))〜\(f.string(from: window.end))"
        var parts: [String] = ["釣れ率 \(window.maxScore)"]
        if let sun, let dawn = sun.civilDawn, let sunrise = sun.sunrise, dawn <= window.end, sunrise.addingTimeInterval(1800) >= window.start {
            parts.append("朝マズメ \(f.string(from: dawn))〜")
        } else if let sun, let sunset = sun.sunset, let dusk = sun.civilDusk, sunset.addingTimeInterval(-1800) <= window.end, dusk >= window.start {
            parts.append("夕マズメ 〜\(f.string(from: dusk))")
        }
        if let e = extremes.filter({ $0.at >= window.start.addingTimeInterval(-3600) && $0.at <= window.end.addingTimeInterval(3600) }).first {
            parts.append("\(e.kind == .high ? "満潮" : "干潮") \(f.string(from: e.at))")
        }
        if let t = airTemperatureC { parts.append("気温 \(Int(t.rounded()))°") }
        return Brief(fireAt: fireAt, windowStart: window.start, windowEnd: window.end, maxScore: window.maxScore, title: title, body: parts.joined(separator: " · "))
    }
}
