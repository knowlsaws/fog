import Foundation

/// 釣れ率スコア（0〜100）の入力。環境は `EnvSnapshot`、日の出入りはスナップショットの値か天文計算で補う。
public struct ScoreInput: Sendable {
    public var at: Date
    public var coordinate: Coordinate
    public var env: EnvSnapshot
    /// 魚種別スコアのとき。nil なら全体
    public var species: String?
    public var timeZone: TimeZone

    public init(at: Date, coordinate: Coordinate, env: EnvSnapshot, species: String? = nil, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        self.at = at; self.coordinate = coordinate; self.env = env; self.species = species; self.timeZone = timeZone
    }

    /// 互換（L0 のテスト形）。座標はスナップショットのもの。
    public init(at: Date, env: EnvSnapshot, minutesToNextTwilight: Double? = nil, minutesToNextTideTurn: Double? = nil) {
        self.init(at: at, coordinate: env.coordinate, env: env)
        self.minutesToNextTwilightOverride = minutesToNextTwilight
        self.minutesToNextTideTurnOverride = minutesToNextTideTurn
    }

    var minutesToNextTwilightOverride: Double?
    var minutesToNextTideTurnOverride: Double?
    /// 推移計算で 1 日 1 回だけ計算した日の出入りと月（点ごとの再計算を避ける）
    var precomputedSun: SunTimes?
    var precomputedMonth: Int?
}

/// 内訳の 1 行（ホームの内訳シート）。
public struct ScoreBreakdown: Hashable, Sendable {
    public enum Factor: String, CaseIterable, Sendable {
        case light      // 時間帯（マズメ・夜）
        case tide       // 潮（変化率・潮名）
        case pressure   // 気圧傾向
        case wind       // 風
        case wave       // 波
        case water      // 水温・季節
        case moon       // 月相
        case personal   // 自分の実績
    }
    public var factor: Factor
    public var points: Double     // 正で上げ、負で下げ
    public var detail: String
    public init(factor: Factor, points: Double, detail: String) { self.factor = factor; self.points = points; self.detail = detail }
}

/// 確度：実況か予報か、気象が無いか。
public enum ScoreConfidence: String, Sendable {
    case observed, forecast, noWeather
}

public struct ScoreResult: Hashable, Sendable {
    public var score: Int            // 0〜100
    public var breakdown: [ScoreBreakdown]
    public var isForecast: Bool
    public var confidence: ScoreConfidence
    public init(score: Int, breakdown: [ScoreBreakdown], isForecast: Bool, confidence: ScoreConfidence) {
        self.score = score; self.breakdown = breakdown; self.isForecast = isForecast; self.confidence = confidence
    }
}

/// ルールベースの基礎スコア＋自分データの重み（F-16, F-17）。
/// 根魚（アイナメ・ソイ）で「今釣れるか」を決める要素は重要度順に：潮が動いているか、光量、風、波・濁り、水温と季節。気圧傾向と月相は補助。
public struct ScoreEngine: Sendable {
    public var personal: PersonalModel?

    public init(personal: PersonalModel? = nil) {
        self.personal = personal
    }

    /// 小数 1 桁の文字列（`String(format:)` は Linux で遅いので使わない）
    static func tenth(_ x: Double) -> String {
        let v = (x * 10).rounded() / 10
        return v == v.rounded() ? "\(Int(v)).0" : "\(v)"
    }

    public func score(_ input: ScoreInput) -> ScoreResult {
        var parts: [ScoreBreakdown] = []
        var total = 50.0
        let env = input.env
        let buckets = ConditionBuckets(input: input)

        // 光量：マズメ（市民薄明〜日の出、日の入〜薄明終わり）が最高、夜はそこそこ、昼は下げ
        let light: Double
        switch buckets.light {
        case .dawn, .dusk: light = 18
        case .nearTwilight: light = 10
        case .night: light = 4
        case .day: light = -6
        }
        parts.append(.init(factor: .light, points: light, detail: buckets.light.label))
        total += light

        // 潮：変化率（cm/時）と潮名
        if let rate = env.tideRateCmPerHour {
            let a = abs(rate)
            let p: Double = a >= 12 ? 12 : (a >= 6 ? 6 : (a < 2 ? -10 : 0))
            parts.append(.init(factor: .tide, points: p, detail: a < 2 ? "潮止まり" : (rate > 0 ? "上げ潮 \(Int(a.rounded())) cm/h" : "下げ潮 \(Int(a.rounded())) cm/h")))
            total += p
        }
        if let name = env.tideName, let tideName = TideName(rawValue: name) {
            let p: Double
            switch tideName {
            case .spring: p = 4
            case .middle: p = 3
            case .neap: p = -2
            case .long: p = -4
            case .young: p = -2
            }
            parts.append(.init(factor: .tide, points: p, detail: name))
            total += p
        }

        // 気圧傾向：下がり始めは活性が上がる、急上昇は渋い
        if let trend = env.pressureTrend3hHPa {
            let p: Double = trend <= -1.5 ? 4 : (trend >= 2 ? -3 : 0)
            parts.append(.init(factor: .pressure, points: p, detail: "\(trend >= 0 ? "+" : "")\(Self.tenth(trend)) hPa/3h"))
            total += p
        }

        // 風：8 m/s 超は悪い（UI の判定と同じ）
        if let w = env.windSpeedMS {
            let p: Double = w <= 3 ? 4 : (w <= 5 ? 0 : (w <= 8 ? -8 : -20))
            parts.append(.init(factor: .wind, points: p, detail: "\(Int(w.rounded())) m/s"))
            total += p
        }

        // 波
        if let h = env.waveHeightM {
            let p: Double = h <= 0.5 ? 3 : (h <= 1.0 ? 0 : (h <= 1.5 ? -8 : -20))
            parts.append(.init(factor: .wave, points: p, detail: "波 \(Self.tenth(h)) m"))
            total += p
        }

        // 水温・季節（北海道の根魚：8〜18℃ が適水温）
        if let sst = env.seaSurfaceTempC {
            let p: Double = (8...18).contains(sst) ? 6 : ((5..<8).contains(sst) || (18...22).contains(sst) ? 0 : -8)
            parts.append(.init(factor: .water, points: p, detail: "水温 \(Self.tenth(sst))℃"))
            total += p
        } else {
            let month = buckets.month
            let p: Double = [4, 5, 6, 10, 11, 12].contains(month) ? 4 : ([7, 8].contains(month) ? -2 : 0)
            parts.append(.init(factor: .water, points: p, detail: "\(month)月"))
            total += p
        }

        // 月相（補助）
        if let age = env.moonAge {
            let p: Double = (age < 2 || age > 27.5 || (13.5...16).contains(age)) ? 2 : 0
            parts.append(.init(factor: .moon, points: p, detail: "月齢 \(Int(age.rounded()))"))
            total += p
        }

        // 自分の実績：釣行が蓄積されるほど重みを上げる
        if let personal {
            let adj = personal.adjustment(for: buckets, species: input.species)
            if adj.points != 0 {
                parts.append(.init(factor: .personal, points: adj.points, detail: adj.detail))
                total += adj.points
            }
        }

        let clamped = max(0, min(100, total))
        let confidence: ScoreConfidence = env.windSpeedMS == nil && env.airTemperatureC == nil ? .noWeather : (env.isForecast ? .forecast : .observed)
        return ScoreResult(score: Int(clamped.rounded()), breakdown: parts, isForecast: env.isForecast, confidence: confidence)
    }
}

/// 条件をバケットに丸める（ルールと自分データの両方で使う）。
public struct ConditionBuckets: Hashable, Sendable {
    public enum Light: String, Sendable {
        case dawn = "朝マズメ", dusk = "夕マズメ", nearTwilight = "マズメ前後", night = "夜", day = "昼"
        var label: String { rawValue }
    }
    public enum Tide: String, Sendable { case rising = "上げ", falling = "下げ", slack = "潮止まり", unknown = "潮不明" }
    public enum Wind: String, Sendable { case calm = "微風", moderate = "そよ風", strong = "強風", unknown = "風不明" }

    public var light: Light
    public var tide: Tide
    public var wind: Wind
    public var tideName: String?
    public var month: Int

    public init(light: Light, tide: Tide, wind: Wind, tideName: String?, month: Int) {
        self.light = light; self.tide = tide; self.wind = wind; self.tideName = tideName; self.month = month
    }

    public init(input: ScoreInput) {
        let env = input.env
        // 光量：スナップショットの日の出入りが無ければ天文計算
        let sun = input.precomputedSun ?? SunCalculator.times(on: input.at, at: input.coordinate, timeZone: input.timeZone)
        let sunrise = env.sunriseAt ?? sun.sunrise
        let sunset = env.sunsetAt ?? sun.sunset
        var light: Light = .day
        if let override = input.minutesToNextTwilightOverride {
            light = override < 60 ? .dawn : (override < 120 ? .nearTwilight : .day)
        } else if let sunrise, let sunset {
            let t = input.at.timeIntervalSince1970
            let dawnStart = (sun.civilDawn ?? sunrise.addingTimeInterval(-30 * 60)).timeIntervalSince1970
            let duskEnd = (sun.civilDusk ?? sunset.addingTimeInterval(30 * 60)).timeIntervalSince1970
            let r = sunrise.timeIntervalSince1970, s = sunset.timeIntervalSince1970
            if t >= dawnStart - 15 * 60 && t <= r + 30 * 60 { light = .dawn }
            else if t >= s - 30 * 60 && t <= duskEnd + 15 * 60 { light = .dusk }
            else if abs(t - r) <= 90 * 60 || abs(t - s) <= 90 * 60 { light = .nearTwilight }
            else if t < dawnStart || t > duskEnd { light = .night }
            else { light = .day }
        }
        self.light = light

        var tide: Tide = .unknown
        if let override = input.minutesToNextTideTurnOverride, override < 20 { tide = .slack }
        if let rate = env.tideRateCmPerHour { tide = abs(rate) < 2 ? .slack : (rate > 0 ? .rising : .falling) }
        self.tide = tide

        if let w = env.windSpeedMS { wind = w <= 3 ? .calm : (w <= 8 ? .moderate : .strong) } else { wind = .unknown }
        tideName = env.tideName
        if let m = input.precomputedMonth {
            month = m
        } else {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = input.timeZone
            month = cal.component(.month, from: input.at)
        }
    }
}
