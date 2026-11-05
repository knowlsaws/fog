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

    public enum DecodeError: Error, Equatable, LocalizedError {
        case invalid, api(String), noPoints
        public var errorDescription: String? {
            switch self {
            case .invalid: return "応答を読めない"
            case .api(let r): return "Open-Meteo: \(r)"
            case .noPoints: return "地点が返らない"
            }
        }
    }

    /// 1 地点分の解読結果（緯度経度は API が格子に寄せた値）
    public struct DecodedPoint: Sendable {
        public var latitude: Double
        public var longitude: Double
        public var times: [Date]
        public var values: [GridForecast.Variable: [Double?]]
    }

    /// 応答（1 地点のオブジェクトか複数地点の配列）を地点ごとに解読する。エラー応答は投げる
    public static func decodePoints(_ data: Data) throws -> [DecodedPoint] {
        let raw: [PointResponse]
        if let list = try? JSONDecoder().decode([PointResponse].self, from: data) {
            raw = list
        } else if let one = try? JSONDecoder().decode(PointResponse.self, from: data) {
            if one.error == true { throw DecodeError.api(one.reason ?? "unknown") }
            raw = [one]
        } else {
            throw DecodeError.invalid
        }
        let map = weatherMap.merging(marineMap) { a, _ in a }
        var out: [DecodedPoint] = []
        for p in raw {
            guard let lat = p.latitude, let lon = p.longitude, let hourly = p.hourly, let timeArr = hourly["time"]?.array else { continue }
            let times = timeArr.compactMap { $0 }.map { Date(timeIntervalSince1970: $0) }
            var values: [GridForecast.Variable: [Double?]] = [:]
            for (key, v) in map {
                guard let arr = hourly[key]?.array else { continue }
                values[v] = v == .currentSpeed ? arr.map { $0.map { $0 / 3.6 } } : arr // km/h → m/s
            }
            out.append(DecodedPoint(latitude: lat, longitude: lon, times: times, values: values))
        }
        return out
    }

    /// 地点を最も近い格子の升に置いて格子にする。API は座標を自分の格子に寄せて返すので、添字ではなく距離で対応させる。
    /// 足りない升（陸・欠落）は nil のまま。時刻は最初の地点のもの
    public static func assemble(points: [DecodedPoint], latitudes: [Double], longitudes: [Double], fetchedAt: Date = .now) throws -> GridForecast {
        let rows = latitudes.count, cols = longitudes.count
        guard rows > 0, cols > 0, let first = points.first(where: { !$0.times.isEmpty }) else { throw DecodeError.noPoints }
        let times = first.times
        let tCount = times.count
        let dLat = rows > 1 ? (latitudes[rows - 1] - latitudes[0]) / Double(rows - 1) : 1
        let dLon = cols > 1 ? (longitudes[cols - 1] - longitudes[0]) / Double(cols - 1) : 1
        var values: [GridForecast.Variable: [Double?]] = [:]
        var filled = Set<Int>()
        for p in points {
            let r = Int(((p.latitude - latitudes[0]) / dLat).rounded()), c = Int(((p.longitude - longitudes[0]) / dLon).rounded())
            guard (0..<rows).contains(r), (0..<cols).contains(c) else { continue }
            let cell = r * cols + c
            // 同じ升に複数来たら近い方（先着で十分）
            guard !filled.contains(cell) else { continue }
            filled.insert(cell)
            for (v, arr) in p.values {
                if values[v] == nil { values[v] = Array(repeating: nil, count: tCount * rows * cols) }
                for t in 0..<min(tCount, arr.count) { values[v]![t * rows * cols + cell] = arr[t] }
            }
        }
        return GridForecast(latitudes: latitudes, longitudes: longitudes, times: times, values: values, fetchedAt: fetchedAt)
    }

    /// 1 回の応答を格子にする（複数回に分けて取ったときは `decodePoints` と `assemble` を使う）
    public static func decode(_ data: Data, latitudes: [Double], longitudes: [Double], fetchedAt: Date = .now) throws -> GridForecast {
        try assemble(points: try decodePoints(data), latitudes: latitudes, longitudes: longitudes, fetchedAt: fetchedAt)
    }

    /// 地点の組を `size` ずつに分けた URL（API の地点数の上限と URL 長を避ける）
    public static func chunkedURLs(marine: Bool, latitudes: [Double], longitudes: [Double], forecastDays: Int = 3, size: Int = 50) -> [URL] {
        var pairs: [(Double, Double)] = []
        for lat in latitudes { for lon in longitudes { pairs.append((lat, lon)) } }
        return stride(from: 0, to: pairs.count, by: max(1, size)).map { start in
            let chunk = Array(pairs[start..<min(pairs.count, start + size)])
            let la = chunk.map { String(format: "%.2f", $0.0) }.joined(separator: ","), lo = chunk.map { String(format: "%.2f", $0.1) }.joined(separator: ",")
            var comps = URLComponents(string: marine ? "https://marine-api.open-meteo.com/v1/marine" : "https://api.open-meteo.com/v1/forecast")!
            var items = [URLQueryItem(name: "latitude", value: la), URLQueryItem(name: "longitude", value: lo),
                         URLQueryItem(name: "hourly", value: (marine ? marineFields : weatherFields).joined(separator: ","))]
            if !marine { items.append(URLQueryItem(name: "wind_speed_unit", value: "ms")) }
            items += [URLQueryItem(name: "forecast_days", value: String(forecastDays)), URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "UTC")]
            comps.queryItems = items
            return comps.url!
        }
    }
}
