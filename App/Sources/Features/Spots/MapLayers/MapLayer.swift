import SwiftUI
import Core

/// 地図に重ねる層（F-43）。色面の変数と、粒子で流す向きの変数、表示の値域と色。
/// Open-Meteo で取れるものは全部並べ、表示する層は設定（`MapLayerSettings`）で選ぶ
enum MapLayer: String, CaseIterable, Identifiable {
    // 気象
    case wind, gust, temperature, apparentTemperature, humidity, dewPoint
    case rain, precipitationProbability, snowfall, snowDepth
    case cloud, cloudLow, cloudMid, cloudHigh, fog, thunder, pressure, uv, freezingLevel
    // 海況
    case wave, wavePeriod, windWave, swell, swellPeriod, secondarySwell, current, sst, seaLevel
    var id: String { rawValue }

    enum Group: String, CaseIterable { case weather = "気象", sea = "海況" }
    var group: Group { isMarine ? .sea : .weather }

    var title: String {
        switch self {
        case .wind: return "風"
        case .gust: return "突風"
        case .temperature: return "気温"
        case .apparentTemperature: return "体感"
        case .humidity: return "湿度"
        case .dewPoint: return "露点"
        case .rain: return "雨"
        case .precipitationProbability: return "降水確率"
        case .snowfall: return "降雪"
        case .snowDepth: return "積雪"
        case .cloud: return "雲"
        case .cloudLow: return "下層雲"
        case .cloudMid: return "中層雲"
        case .cloudHigh: return "上層雲"
        case .fog: return "霧"
        case .thunder: return "雷"
        case .pressure: return "気圧"
        case .uv: return "UV"
        case .freezingLevel: return "凍結高度"
        case .wave: return "波"
        case .wavePeriod: return "波の周期"
        case .windWave: return "風波"
        case .swell: return "うねり"
        case .swellPeriod: return "うねり周期"
        case .secondarySwell: return "第2うねり"
        case .current: return "流れ"
        case .sst: return "水温"
        case .seaLevel: return "潮位"
        }
    }

    /// 設定画面の説明
    var detail: String {
        switch self {
        case .fog: return "視程が短いほど濃く（1 km 未満が霧）"
        case .thunder: return "大気の不安定さ（CAPE）。1,000 以上で雷の可能性"
        case .snowfall: return "1 時間の降雪（cm）"
        case .snowDepth: return "積雪の深さ"
        case .seaLevel: return "平均海面からの高さ（潮汐＋気圧）"
        case .secondarySwell: return "2 つ目のうねり成分"
        case .freezingLevel: return "0℃ になる高さ"
        default: return ""
        }
    }

    var isMarine: Bool { [.wave, .wavePeriod, .windWave, .swell, .swellPeriod, .secondarySwell, .current, .sst, .seaLevel].contains(self) }

    /// 色面の変数
    var scalar: GridForecast.Variable {
        switch self {
        case .wind: return .windSpeed
        case .gust: return .windGust
        case .temperature: return .airTemperature
        case .apparentTemperature: return .apparentTemperature
        case .humidity: return .humidity
        case .dewPoint: return .dewPoint
        case .rain: return .precipitation
        case .precipitationProbability: return .precipitationProbability
        case .snowfall: return .snowfall
        case .snowDepth: return .snowDepth
        case .cloud: return .cloudCover
        case .cloudLow: return .cloudLow
        case .cloudMid: return .cloudMid
        case .cloudHigh: return .cloudHigh
        case .fog: return .visibility
        case .thunder: return .cape
        case .pressure: return .pressure
        case .uv: return .uvIndex
        case .freezingLevel: return .freezingLevel
        case .wave: return .waveHeight
        case .wavePeriod: return .wavePeriod
        case .windWave: return .windWaveHeight
        case .swell: return .swellHeight
        case .swellPeriod: return .swellPeriod
        case .secondarySwell: return .secondarySwellHeight
        case .current: return .currentSpeed
        case .sst: return .seaSurfaceTemperature
        case .seaLevel: return .seaLevel
        }
    }

    /// 粒子で流す向き（速さの変数・向きの変数・「吹いてくる向き」か）。無い層は色面だけ
    var vector: (speed: GridForecast.Variable, direction: GridForecast.Variable, from: Bool)? {
        switch self {
        case .wind: return (.windSpeed, .windDirection, true)
        case .gust: return (.windGust, .windDirection, true)
        case .wave, .wavePeriod: return (.waveHeight, .waveDirection, false)
        case .windWave: return (.windWaveHeight, .windWaveDirection, false)
        case .swell, .swellPeriod: return (.swellHeight, .swellDirection, false)
        case .secondarySwell: return (.secondarySwellHeight, .secondarySwellDirection, false)
        case .current: return (.currentSpeed, .currentDirection, false)
        default: return nil
        }
    }

    /// 粒子の速さの倍率（1 の値で 1 秒に進む距離 m）。見える速さに誇張する
    var particleScale: Double {
        switch self {
        case .wind, .gust: return 900
        case .wave, .wavePeriod, .windWave, .swell, .swellPeriod, .secondarySwell: return 3000
        case .current: return 15_000
        default: return 0
        }
    }

    var unit: String {
        switch self {
        case .wind, .gust, .current: return "m/s"
        case .temperature, .apparentTemperature, .dewPoint, .sst: return "°"
        case .rain: return "mm"
        case .snowfall: return "cm"
        case .snowDepth, .wave, .windWave, .swell, .secondarySwell, .seaLevel, .freezingLevel, .fog: return "m"
        case .humidity, .precipitationProbability, .cloud, .cloudLow, .cloudMid, .cloudHigh: return "%"
        case .pressure: return "hPa"
        case .uv: return ""
        case .thunder: return "J/kg"
        case .wavePeriod, .swellPeriod: return "s"
        }
    }

    /// 表示の値域（固定。凡例と色が日によって変わらないように）
    var range: ClosedRange<Double> {
        switch self {
        case .wind: return 0...20
        case .gust: return 0...30
        case .temperature, .apparentTemperature: return -5...30
        case .dewPoint: return -10...25
        case .humidity, .precipitationProbability, .cloud, .cloudLow, .cloudMid, .cloudHigh: return 0...100
        case .rain: return 0...10
        case .snowfall: return 0...5
        case .snowDepth: return 0...1
        case .fog: return 0...10_000
        case .thunder: return 0...2000
        case .pressure: return 980...1040
        case .uv: return 0...11
        case .freezingLevel: return 0...4000
        case .wave, .windWave, .swell, .secondarySwell: return 0...4
        case .wavePeriod, .swellPeriod: return 2...16
        case .current: return 0...1.5
        case .sst: return 0...25
        case .seaLevel: return -1.5...1.5
        }
    }

    /// 値を 0〜1 に。霧は視程が短いほど 1（色が濃い）
    func normalized(_ value: Double) -> Double {
        let t = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
        return self == .fog ? 1 - t : t
    }

    /// 色の段（0〜1 → RGB）
    var stops: [(Double, (Double, Double, Double))] {
        switch self {
        case .wind, .gust, .current:
            return [(0, (0.38, 0.44, 0.72)), (0.15, (0.24, 0.60, 0.70)), (0.3, (0.31, 0.65, 0.42)), (0.5, (0.61, 0.76, 0.31)),
                    (0.65, (0.91, 0.75, 0.30)), (0.8, (0.88, 0.46, 0.24)), (1, (0.69, 0.25, 0.54))]
        case .temperature, .apparentTemperature, .dewPoint, .sst:
            return [(0, (0.36, 0.25, 0.70)), (0.2, (0.23, 0.44, 0.82)), (0.4, (0.25, 0.69, 0.69)), (0.6, (0.56, 0.81, 0.35)),
                    (0.8, (0.94, 0.82, 0.30)), (1, (0.90, 0.45, 0.18))]
        case .rain, .precipitationProbability:
            return [(0, (0.10, 0.12, 0.18)), (0.1, (0.20, 0.35, 0.60)), (0.3, (0.25, 0.60, 0.85)), (0.6, (0.40, 0.85, 0.60)), (1, (0.95, 0.85, 0.30))]
        case .snowfall, .snowDepth:
            return [(0, (0.10, 0.12, 0.20)), (0.2, (0.35, 0.50, 0.80)), (0.5, (0.65, 0.78, 0.95)), (1, (0.97, 0.97, 1.0))]
        case .cloud, .cloudLow, .cloudMid, .cloudHigh:
            return [(0, (0.10, 0.30, 0.60)), (0.5, (0.45, 0.50, 0.58)), (1, (0.90, 0.90, 0.92))]
        case .fog:
            return [(0, (0.10, 0.12, 0.18)), (0.4, (0.40, 0.42, 0.50)), (0.7, (0.70, 0.70, 0.76)), (1, (0.95, 0.95, 0.97))]
        case .thunder:
            return [(0, (0.10, 0.12, 0.18)), (0.2, (0.30, 0.25, 0.60)), (0.5, (0.75, 0.30, 0.65)), (0.8, (0.95, 0.55, 0.25)), (1, (1.0, 0.95, 0.40))]
        case .humidity:
            return [(0, (0.80, 0.60, 0.30)), (0.5, (0.45, 0.65, 0.55)), (1, (0.15, 0.40, 0.85))]
        case .pressure:
            return [(0, (0.35, 0.20, 0.60)), (0.3, (0.25, 0.50, 0.80)), (0.5, (0.35, 0.70, 0.50)), (0.7, (0.90, 0.80, 0.35)), (1, (0.85, 0.35, 0.25))]
        case .uv:
            return [(0, (0.20, 0.60, 0.30)), (0.3, (0.90, 0.85, 0.30)), (0.6, (0.95, 0.50, 0.20)), (0.8, (0.85, 0.20, 0.25)), (1, (0.60, 0.20, 0.70))]
        case .freezingLevel:
            return [(0, (0.80, 0.85, 0.95)), (0.5, (0.35, 0.60, 0.85)), (1, (0.25, 0.30, 0.65))]
        case .wave, .windWave, .swell, .secondarySwell:
            return [(0, (0.20, 0.35, 0.65)), (0.25, (0.25, 0.65, 0.80)), (0.5, (0.45, 0.80, 0.50)), (0.75, (0.95, 0.80, 0.30)), (1, (0.80, 0.30, 0.50))]
        case .wavePeriod, .swellPeriod:
            return [(0, (0.25, 0.40, 0.70)), (0.5, (0.40, 0.75, 0.70)), (1, (0.95, 0.85, 0.35))]
        case .seaLevel:
            return [(0, (0.25, 0.35, 0.75)), (0.5, (0.35, 0.60, 0.55)), (1, (0.90, 0.55, 0.25))]
        }
    }

    /// 値 → 色（0〜255）
    func rgb(_ value: Double) -> (UInt8, UInt8, UInt8) {
        let t = normalized(value)
        let s = stops
        var i = 0
        while i + 1 < s.count, s[i + 1].0 < t { i += 1 }
        let (t0, c0) = s[i], (t1, c1) = s[min(i + 1, s.count - 1)]
        let f = t1 > t0 ? (t - t0) / (t1 - t0) : 0
        func mix(_ a: Double, _ b: Double) -> UInt8 { UInt8(max(0, min(255, (a + (b - a) * f) * 255))) }
        return (mix(c0.0, c1.0), mix(c0.1, c1.1), mix(c0.2, c1.2))
    }

    /// 凡例の目盛り
    var legendTicks: [Double] {
        let r = range
        return [r.lowerBound, r.lowerBound + (r.upperBound - r.lowerBound) * 0.5, r.upperBound]
    }

    func format(_ v: Double) -> String {
        switch self {
        case .wave, .windWave, .swell, .secondarySwell, .current, .snowDepth, .seaLevel: return String(format: "%.1f", v)
        case .fog: return v >= 1000 ? String(format: "%.0f km", v / 1000) : String(format: "%.0f m", v)
        default: return String(format: "%.0f", v)
        }
    }

    /// 既定で表示する層
    static let defaultEnabled: [MapLayer] = [.wind, .gust, .temperature, .rain, .snowfall, .cloud, .fog, .thunder, .pressure, .wave, .swell, .current, .sst]
}

/// 地図レイヤーの設定（F-43）：表示する層・粒子・透明度
enum MapLayerSettings {
    private static let enabledKey = "fog.mapLayers.enabled"
    private static let particlesKey = "fog.mapLayers.particles"
    private static let densityKey = "fog.mapLayers.density"
    private static let opacityKey = "fog.mapLayers.opacity"

    enum Density: String, CaseIterable, Identifiable {
        case low, medium, high
        var id: String { rawValue }
        var label: String { self == .low ? "少" : (self == .medium ? "中" : "多") }
        var count: Int { self == .low ? 400 : (self == .medium ? 800 : 1400) }
    }

    static var enabled: [MapLayer] {
        get {
            guard let raw = UserDefaults.standard.stringArray(forKey: enabledKey) else { return MapLayer.defaultEnabled }
            let set = Set(raw)
            return MapLayer.allCases.filter { set.contains($0.rawValue) }
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: enabledKey) }
    }

    static func isEnabled(_ l: MapLayer) -> Bool { enabled.contains(l) }

    static func setEnabled(_ on: Bool, _ l: MapLayer) {
        var list = enabled
        if on, !list.contains(l) { list.append(l) } else if !on { list.removeAll { $0 == l } }
        enabled = list
    }

    static var particles: Bool {
        get { UserDefaults.standard.object(forKey: particlesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: particlesKey) }
    }

    static var density: Density {
        get { Density(rawValue: UserDefaults.standard.string(forKey: densityKey) ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: densityKey) }
    }

    /// 色面の濃さ 0.15〜0.8（既定 0.4。地図が透けて見える濃さ。2026-11-05 実機フィードバック）
    static let defaultOpacity = 0.4
    static var opacity: Double {
        get { let v = UserDefaults.standard.double(forKey: opacityKey); return v == 0 ? defaultOpacity : min(0.8, max(0.15, v)) }
        set { UserDefaults.standard.set(newValue, forKey: opacityKey) }
    }
}
