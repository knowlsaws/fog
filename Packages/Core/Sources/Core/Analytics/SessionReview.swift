import Foundation

/// 釣行後の答え合わせ（F-29）：その日の釣れ率の推移に実際の釣果を重ね、スコアが当たっていたかを数字にする。
public enum SessionReview {
    public struct Result: Hashable, Sendable {
        /// 釣行中の平均釣れ率
        public var meanScore: Double
        /// 釣れた瞬間の釣れ率の平均（釣果なしは nil）
        public var meanScoreAtCatch: Double?
        /// 釣れた瞬間に釣れ率が `goodThreshold` 以上だった割合（釣果なしは nil）
        public var hitRate: Double?
        /// 釣果ごとの（時刻, 釣れ率）
        public var catchScores: [(Date, Int)]

        public static func == (l: Result, r: Result) -> Bool {
            l.meanScore == r.meanScore && l.meanScoreAtCatch == r.meanScoreAtCatch && l.hitRate == r.hitRate
                && l.catchScores.map { $0.0 } == r.catchScores.map { $0.0 } && l.catchScores.map { $0.1 } == r.catchScores.map { $0.1 }
        }
        public func hash(into h: inout Hasher) { h.combine(meanScore); h.combine(meanScoreAtCatch); h.combine(hitRate) }

        /// 1 行の評価
        public var verdict: String {
            guard let hit = hitRate, let atCatch = meanScoreAtCatch else { return "釣果なし" }
            if hit >= 0.7 { return "よく当たった（釣れた時の平均 \(Int(atCatch.rounded()))）" }
            if hit >= 0.4 { return "まずまず（釣れた時の平均 \(Int(atCatch.rounded()))）" }
            return "外れた（釣れた時の平均 \(Int(atCatch.rounded()))）"
        }
    }

    /// `points` は釣行の時間範囲の推移。`catchTimes` は釣れた時刻。`from`〜`to` の範囲で平均を取る。
    public static func evaluate(points: [ScorePoint], catchTimes: [Date], from: Date, to: Date, goodThreshold: Int = 60) -> Result? {
        let inRange = points.filter { $0.at >= from && $0.at <= to }
        guard !inRange.isEmpty else { return nil }
        let mean = Double(inRange.reduce(0) { $0 + $1.score }) / Double(inRange.count)
        let scores: [(Date, Int)] = catchTimes.sorted().compactMap { t in
            guard let p = points.min(by: { abs($0.at.timeIntervalSince(t)) < abs($1.at.timeIntervalSince(t)) }) else { return nil }
            return (t, p.score)
        }
        guard !scores.isEmpty else { return Result(meanScore: mean, meanScoreAtCatch: nil, hitRate: nil, catchScores: []) }
        let atCatch = Double(scores.reduce(0) { $0 + $1.1 }) / Double(scores.count)
        let hits = scores.filter { $0.1 >= goodThreshold }.count
        return Result(meanScore: mean, meanScoreAtCatch: atCatch, hitRate: Double(hits) / Double(scores.count), catchScores: scores)
    }
}
