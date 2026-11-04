import Foundation

/// 環境スナップショット（§2）。釣行中は30分ごと、釣果時はその瞬間の値。
/// 取得できなかった項目は nil のまま保存する。`isForecast` は予報値で埋めたことを示し、実況値が取れたら差し替える（F-06）。
public struct EnvSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var at: Date
    public var coordinate: Coordinate

    // 気象（WeatherKit）
    public var airTemperatureC: Double?
    public var humidity: Double?            // 0〜1
    public var conditionCode: String?       // WeatherKit の WeatherCondition rawValue
    public var windSpeedMS: Double?
    public var windGustMS: Double?
    public var windDirectionDeg: Double?    // 風の吹いてくる方向
    public var pressureHPa: Double?
    public var cloudCover: Double?          // 0〜1
    public var precipitationMM: Double?     // 直近1時間
    public var precipitationChance: Double? // 降水確率 0〜1
    public var visibilityM: Double?

    // 気圧（端末の気圧計）
    public var measuredPressureHPa: Double?
    public var pressureTrend3hHPa: Double?  // 直近3時間の変化量（正で上昇）

    // 潮汐（端末内推算）
    public var tideLevelCm: Double?
    public var tideRateCmPerHour: Double?   // 正で上げ潮
    public var tideName: String?            // 大潮・中潮・小潮・長潮・若潮
    public var nextHighTideAt: Date?
    public var nextLowTideAt: Date?

    // 海況（Open-Meteo Marine）
    public var waveHeightM: Double?
    public var wavePeriodS: Double?
    public var waveDirectionDeg: Double?
    public var swellHeightM: Double?
    public var seaSurfaceTempC: Double?
    public var oceanCurrentMS: Double?

    // 天文（端末内計算）
    public var sunriseAt: Date?
    public var sunsetAt: Date?
    public var moonAge: Double?

    public var isForecast: Bool

    public init(id: UUID = UUID(), at: Date, coordinate: Coordinate, isForecast: Bool = false) {
        self.id = id
        self.at = at
        self.coordinate = coordinate
        self.isForecast = isForecast
    }
}
