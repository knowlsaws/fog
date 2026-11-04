import Foundation

/// 釣れ率スコアの入力。L7 で項目を増やす。
public struct ScoreInput: Sendable {
    public var at: Date
    public var env: EnvSnapshot
    public var minutesToNextTwilight: Double?   // 次のマズメまで
    public var minutesToNextTideTurn: Double?   // 次の満潮・干潮まで
    public init(at: Date, env: EnvSnapshot, minutesToNextTwilight: Double? = nil, minutesToNextTideTurn: Double? = nil) {
        self.at = at; self.env = env; self.minutesToNextTwilight = minutesToNextTwilight; self.minutesToNextTideTurn = minutesToNextTideTurn
    }
}

public struct ScoreBreakdown: Sendable {
    public var factor: String
    public var points: Double     // 正で上げ、負で下げ
}

public struct ScoreResult: Sendable {
    public var score: Int            // 0〜100
    public var breakdown: [ScoreBreakdown]
    public var isForecast: Bool
}

/// ルールベースの釣れ率（L0 は骨組み）。L7 で係数と自分データの重み学習を実装する。
public struct ScoreEngine: Sendable {
    public init() {}

    public func score(_ input: ScoreInput) -> ScoreResult {
        var parts: [ScoreBreakdown] = []
        var total = 50.0

        if let w = input.env.windSpeedMS {
            let p: Double = w < 3 ? 5 : (w < 5 ? 0 : (w < 8 ? -10 : -25))
            parts.append(.init(factor: "wind", points: p)); total += p
        }
        if let rate = input.env.tideRateCmPerHour {
            let p: Double = abs(rate) > 10 ? 10 : (abs(rate) > 4 ? 4 : -8)
            parts.append(.init(factor: "tide", points: p)); total += p
        }
        if let m = input.minutesToNextTwilight {
            let p: Double = m < 60 ? 15 : (m < 120 ? 6 : 0)
            parts.append(.init(factor: "light", points: p)); total += p
        }
        if let trend = input.env.pressureTrend3hHPa {
            let p: Double = trend < -1 ? 4 : (trend > 2 ? -3 : 0)
            parts.append(.init(factor: "pressure", points: p)); total += p
        }
        let clamped = max(0, min(100, total))
        return ScoreResult(score: Int(clamped.rounded()), breakdown: parts, isForecast: input.env.isForecast)
    }
}
