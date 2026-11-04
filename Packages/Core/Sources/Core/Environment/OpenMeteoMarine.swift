import Foundation

/// Open-Meteo Marine API の URL 組み立てと応答の解読（通信は App 側）。
/// https://open-meteo.com/en/docs/marine-weather-api — CC BY 4.0。設定画面にクレジットを表示する。
public enum OpenMeteoMarine {
    public static let creditText = "Weather data by Open-Meteo.com"
    public static let creditURL = "https://open-meteo.com/"
    public static let hourlyFields = ["wave_height", "wave_direction", "wave_period", "swell_wave_height", "swell_wave_period",
                                      "sea_surface_temperature", "ocean_current_velocity"]

    /// 位置は 0.01°（約 1 km）に丸めて送る（§6 位置情報は必要な精度に丸める）。
    public static func url(for c: Coordinate, forecastDays: Int = 7) -> URL {
        let lat = (c.latitude * 100).rounded() / 100
        let lon = (c.longitude * 100).rounded() / 100
        var comps = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
            URLQueryItem(name: "hourly", value: hourlyFields.joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "UTC"),
        ]
        return comps.url!
    }

    struct Response: Decodable {
        struct Hourly: Decodable {
            var time: [Double]
            var wave_height: [Double?]?
            var wave_direction: [Double?]?
            var wave_period: [Double?]?
            var swell_wave_height: [Double?]?
            var swell_wave_period: [Double?]?
            var sea_surface_temperature: [Double?]?
            var ocean_current_velocity: [Double?]?
        }
        var latitude: Double?
        var longitude: Double?
        var hourly: Hourly?
        var error: Bool?
        var reason: String?
    }

    public enum DecodeResult: Equatable {
        /// 値あり
        case samples([MarineSample])
        /// 格子点が陸（値が全部 null）
        case land
        /// API のエラー応答
        case error(String)
    }

    /// 応答 JSON を解読。全時刻で波高が null なら陸扱い。
    public static func decode(_ data: Data) -> DecodeResult {
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return .error("解読できない応答") }
        if r.error == true { return .error(r.reason ?? "unknown") }
        guard let h = r.hourly else { return .error("hourly がない") }
        func at(_ arr: [Double?]?, _ i: Int) -> Double? {
            guard let arr, i < arr.count else { return nil }
            return arr[i]
        }
        var out: [MarineSample] = []
        for (i, t) in h.time.enumerated() {
            let wave = at(h.wave_height, i)
            let sst = at(h.sea_surface_temperature, i)
            if wave == nil && sst == nil { continue }
            out.append(MarineSample(
                at: Date(timeIntervalSince1970: t),
                waveHeightM: wave,
                wavePeriodS: at(h.wave_period, i),
                waveDirectionDeg: at(h.wave_direction, i),
                swellHeightM: at(h.swell_wave_height, i),
                swellPeriodS: at(h.swell_wave_period, i),
                seaSurfaceTempC: sst,
                oceanCurrentMS: at(h.ocean_current_velocity, i).map { $0 / 3.6 } // km/h → m/s
            ))
        }
        return out.isEmpty ? .land : .samples(out)
    }
}
