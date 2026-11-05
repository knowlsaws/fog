import Foundation

/// Open-Meteo の複数地点呼び出しで、釣り場の周りの格子をまとめて取る（F-43）。通信は App 側。
/// 気象は Forecast API（約 11 km）、海況は Marine API（約 5 km）。どちらも CC BY 4.0、クレジットは設定の情報源に表示済み。
public enum OpenMeteoGrid {
    public static let weatherFields = ["wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "temperature_2m", "apparent_temperature",
                                       "relative_humidity_2m", "dew_point_2m", "precipitation", "precipitation_probability", "snowfall", "snow_depth",
                                       "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "visibility", "cape", "pressure_msl",
                                       "uv_index", "freezing_level_height"]
    public static let marineFields = ["wave_height", "wave_direction", "wave_period", "wind_wave_height", "wind_wave_direction", "wind_wave_period",
                                      "swell_wave_height", "swell_wave_direction", "swell_wave_period",
                                      "secondary_swell_wave_height", "secondary_swell_wave_direction", "secondary_swell_wave_period",
                                      "ocean_current_velocity", "ocean_current_direction", "sea_surface_temperature", "sea_level_height_msl"]

    /// 中心から `spanKm` 四方を `n` × `n` の点に。緯度・経度は 0.01° に丸める
    public static func grid(center: Coordinate, spanKm: Double, n: Int) -> (latitudes: [Double], longitudes: [Double]) {
        let n = max(2, n)
        let dLat = spanKm / 111.32
        let dLon = spanKm / (111.32 * cos(center.latitude * .pi / 180))
        func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
        let lats = (0..<n).map { round2(center.latitude - dLat / 2 + dLat * Double($0) / Double(n - 1)) }
        let lons = (0..<n).map { round2(center.longitude - dLon / 2 + dLon * Double($0) / Double(n - 1)) }
        return (lats, lons)
    }

    /// 全組み合わせ（行優先：緯度ごとに経度を並べる）
    static func pairs(latitudes: [Double], longitudes: [Double]) -> (lat: String, lon: String) {
        var la: [String] = [], lo: [String] = []
        for lat in latitudes { for lon in longitudes { la.append(String(format: "%.2f", lat)); lo.append(String(format: "%.2f", lon)) } }
        return (la.joined(separator: ","), lo.joined(separator: ","))
    }

    public static func weatherURL(latitudes: [Double], longitudes: [Double], forecastDays: Int = 3) -> URL {
        let p = pairs(latitudes: latitudes, longitudes: longitudes)
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: p.lat), URLQueryItem(name: "longitude", value: p.lon),
            URLQueryItem(name: "hourly", value: weatherFields.joined(separator: ",")),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "UTC"),
        ]
        return comps.url!
    }

    public static func marineURL(latitudes: [Double], longitudes: [Double], forecastDays: Int = 3) -> URL {
        let p = pairs(latitudes: latitudes, longitudes: longitudes)
        var comps = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: p.lat), URLQueryItem(name: "longitude", value: p.lon),
            URLQueryItem(name: "hourly", value: marineFields.joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "UTC"),
        ]
        return comps.url!
    }

    /// 1 地点分の応答（複数地点だと配列で返る）
    struct PointResponse: Decodable {
        var latitude: Double?
        var longitude: Double?
        var hourly: [String: HourlyValue]?
        var error: Bool?
        var reason: String?
    }

    /// hourly の中身は time（数値配列）と変数（数値か null の配列）
    enum HourlyValue: Decodable {
        case numbers([Double?])
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            self = .numbers(try c.decode([Double?].self))
        }
        var array: [Double?] { switch self { case .numbers(let a): return a } }
    }

    static let weatherMap: [String: GridForecast.Variable] = [
        "wind_speed_10m": .windSpeed, "wind_direction_10m": .windDirection, "wind_gusts_10m": .windGust, "temperature_2m": .airTemperature,
        "apparent_temperature": .apparentTemperature, "relative_humidity_2m": .humidity, "dew_point_2m": .dewPoint,
        "precipitation": .precipitation, "precipitation_probability": .precipitationProbability, "snowfall": .snowfall, "snow_depth": .snowDepth,
        "cloud_cover": .cloudCover, "cloud_cover_low": .cloudLow, "cloud_cover_mid": .cloudMid, "cloud_cover_high": .cloudHigh,
        "visibility": .visibility, "cape": .cape, "pressure_msl": .pressure, "uv_index": .uvIndex, "freezing_level_height": .freezingLevel,
    ]
    static let marineMap: [String: GridForecast.Variable] = [
        "wave_height": .waveHeight, "wave_direction": .waveDirection, "wave_period": .wavePeriod,
        "wind_wave_height": .windWaveHeight, "wind_wave_direction": .windWaveDirection, "wind_wave_period": .windWavePeriod,
        "swell_wave_height": .swellHeight, "swell_wave_direction": .swellDirection, "swell_wave_period": .swellPeriod,
        "secondary_swell_wave_height": .secondarySwellHeight, "secondary_swell_wave_direction": .secondarySwellDirection, "secondary_swell_wave_period": .secondarySwellPeriod,
        "ocean_current_velocity": .currentSpeed, "ocean_current_direction": .currentDirection,
        "sea_surface_temperature": .seaSurfaceTemperature, "sea_level_height_msl": .seaLevel,
    ]

    public enum DecodeError: Error, Equatable { case invalid, api(String), countMismatch }

    /// 応答を格子にする。地点の並びは `pairs` と同じ（行優先）。陸の海況は null のまま
    public static func decode(_ data: Data, latitudes: [Double], longitudes: [Double], fetchedAt: Date = .now) throws -> GridForecast {
        let points: [PointResponse]
        if let list = try? JSONDecoder().decode([PointResponse].self, from: data) {
            points = list
        } else if let one = try? JSONDecoder().decode(PointResponse.self, from: data) {
            if one.error == true { throw DecodeError.api(one.reason ?? "unknown") }
            points = [one]
        } else {
            throw DecodeError.invalid
        }
        let rows = latitudes.count, cols = longitudes.count
        guard points.count == rows * cols else { throw DecodeError.countMismatch }
        guard let timeArr = points.first(where: { $0.hourly?["time"] != nil })?.hourly?["time"]?.array else { throw DecodeError.invalid }
        let times = timeArr.compactMap { $0 }.map { Date(timeIntervalSince1970: $0) }
        let tCount = times.count
        var values: [GridForecast.Variable: [Double?]] = [:]
        let map = weatherMap.merging(marineMap) { a, _ in a }
        for (p, point) in points.enumerated() {
            let r = p / cols, c = p % cols
            guard let hourly = point.hourly else { continue }
            for (key, v) in map {
                guard let arr = hourly[key]?.array else { continue }
                if values[v] == nil { values[v] = Array(repeating: nil, count: tCount * rows * cols) }
                for t in 0..<min(tCount, arr.count) {
                    var val = arr[t]
                    if v == .currentSpeed, let x = val { val = x / 3.6 } // km/h → m/s
                    values[v]![t * rows * cols + r * cols + c] = val
                }
            }
        }
        return GridForecast(latitudes: latitudes, longitudes: longitudes, times: times, values: values, fetchedAt: fetchedAt)
    }
}
