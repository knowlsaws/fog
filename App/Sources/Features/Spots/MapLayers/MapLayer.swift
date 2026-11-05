import SwiftUI
import Core

/// 地図に重ねる層（F-43）。色面の変数と、粒子で流す向きの変数、表示の値域と色。
enum MapLayer: String, CaseIterable, Identifiable {
    case wind, gust, temperature, rain, cloud, pressure, wave, swell, current, sst
    var id: String { rawValue }

    var title: String {
        switch self {
        case .wind: return "風"
        case .gust: return "突風"
        case .temperature: return "気温"
        case .rain: return "雨"
        case .cloud: return "雲"
        case .pressure: return "気圧"
        case .wave: return "波"
        case .swell: return "うねり"
        case .current: return "流れ"
        case .sst: return "水温"
        }
    }

    var isMarine: Bool { [.wave, .swell, .current, .sst].contains(self) }

    /// 色面の変数
    var scalar: GridForecast.Variable {
        switch self {
        case .wind: return .windSpeed
        case .gust: return .windGust
        case .temperature: return .airTemperature
        case .rain: return .precipitation
        case .cloud: return .cloudCover
        case .pressure: return .pressure
        case .wave: return .waveHeight
        case .swell: return .swellHeight
        case .current: return .currentSpeed
        case .sst: return .seaSurfaceTemperature
        }
    }

    /// 粒子で流す向き（速さの変数・向きの変数・「吹いてくる向き」か）。無い層は色面だけ
    var vector: (speed: GridForecast.Variable, direction: GridForecast.Variable, from: Bool)? {
        switch self {
        case .wind: return (.windSpeed, .windDirection, true)
        case .gust: return (.windGust, .windDirection, true)
        case .wave: return (.waveHeight, .waveDirection, false)
        case .swell: return (.swellHeight, .swellDirection, false)
        case .current: return (.currentSpeed, .currentDirection, false)
        default: return nil
        }
    }

    /// 粒子の速さの倍率（1 の値で 1 秒に進む距離 m）。見える速さに誇張する
    var particleScale: Double {
        switch self {
        case .wind, .gust: return 900
        case .wave, .swell: return 3000
        case .current: return 15_000
        default: return 0
        }
    }

    var unit: String {
        switch self {
        case .wind, .gust, .current: return "m/s"
        case .temperature, .sst: return "°"
        case .rain: return "mm"
        case .cloud: return "%"
        case .pressure: return "hPa"
        case .wave, .swell: return "m"
        }
    }

    /// 表示の値域（固定。凡例と色が日によって変わらないように）
    var range: ClosedRange<Double> {
        switch self {
        case .wind: return 0...20
        case .gust: return 0...30
        case .temperature: return -5...30
        case .rain: return 0...10
        case .cloud: return 0...100
        case .pressure: return 980...1040
        case .wave: return 0...4
        case .swell: return 0...4
        case .current: return 0...1.5
        case .sst: return 0...25
        }
    }

    /// 色の段（0〜1 → RGB）
    var stops: [(Double, (Double, Double, Double))] {
        switch self {
        case .wind, .gust, .current:
            return [(0, (0.38, 0.44, 0.72)), (0.15, (0.24, 0.60, 0.70)), (0.3, (0.31, 0.65, 0.42)), (0.5, (0.61, 0.76, 0.31)),
                    (0.65, (0.91, 0.75, 0.30)), (0.8, (0.88, 0.46, 0.24)), (1, (0.69, 0.25, 0.54))]
        case .temperature, .sst:
            return [(0, (0.36, 0.25, 0.70)), (0.2, (0.23, 0.44, 0.82)), (0.4, (0.25, 0.69, 0.69)), (0.6, (0.56, 0.81, 0.35)),
                    (0.8, (0.94, 0.82, 0.30)), (1, (0.90, 0.45, 0.18))]
        case .rain:
            return [(0, (0.10, 0.12, 0.18)), (0.1, (0.20, 0.35, 0.60)), (0.3, (0.25, 0.60, 0.85)), (0.6, (0.40, 0.85, 0.60)), (1, (0.95, 0.85, 0.30))]
        case .cloud:
            return [(0, (0.10, 0.30, 0.60)), (0.5, (0.45, 0.50, 0.58)), (1, (0.90, 0.90, 0.92))]
        case .pressure:
            return [(0, (0.35, 0.20, 0.60)), (0.3, (0.25, 0.50, 0.80)), (0.5, (0.35, 0.70, 0.50)), (0.7, (0.90, 0.80, 0.35)), (1, (0.85, 0.35, 0.25))]
        case .wave, .swell:
            return [(0, (0.20, 0.35, 0.65)), (0.25, (0.25, 0.65, 0.80)), (0.5, (0.45, 0.80, 0.50)), (0.75, (0.95, 0.80, 0.30)), (1, (0.80, 0.30, 0.50))]
        }
    }

    /// 値 → 色（0〜255）
    func rgb(_ value: Double) -> (UInt8, UInt8, UInt8) {
        let t = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
        let s = stops
        var i = 0
        while i + 1 < s.count, s[i + 1].0 < t { i += 1 }
        let (t0, c0) = s[i], (t1, c1) = s[min(i + 1, s.count - 1)]
        let f = t1 > t0 ? (t - t0) / (t1 - t0) : 0
        func mix(_ a: Double, _ b: Double) -> UInt8 { UInt8(max(0, min(255, (a + (b - a) * f) * 255))) }
        return (mix(c0.0, c1.0), mix(c0.1, c1.1), mix(c0.2, c1.2))
    }

    func color(_ value: Double) -> Color {
        let c = rgb(value)
        return Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
    }

    /// 凡例の目盛り
    var legendTicks: [Double] {
        let r = range
        return [r.lowerBound, r.lowerBound + (r.upperBound - r.lowerBound) * 0.5, r.upperBound]
    }

    func format(_ v: Double) -> String {
        switch self {
        case .wave, .swell, .current: return String(format: "%.1f", v)
        default: return String(format: "%.0f", v)
        }
    }
}
