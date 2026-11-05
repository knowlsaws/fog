import XCTest
@testable import Core

final class GridForecastTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_762_300_800)

    /// 2×2 の格子、2 時刻。風速は西→東で 2→4、南→北で +0。時刻で +1
    func makeGrid() -> GridForecast {
        var values: [GridForecast.Variable: [Double?]] = [:]
        values[.windSpeed] = [2, 4, 2, 4, 3, 5, 3, 5]
        values[.windDirection] = [350, 10, 350, 10, 350, 10, 350, 10]
        values[.seaSurfaceTemperature] = [10, nil, 10, nil, 10, nil, 10, nil]
        return GridForecast(latitudes: [41.0, 42.0], longitudes: [140.0, 141.0], times: [t0, t0.addingTimeInterval(3600)], values: values)
    }

    func testGridBuilder() {
        let g = OpenMeteoGrid.grid(center: Coordinate(latitude: 41.8, longitude: 140.7), spanKm: 80, n: 5)
        XCTAssertEqual(g.latitudes.count, 5); XCTAssertEqual(g.longitudes.count, 5)
        XCTAssertEqual(g.latitudes[2], 41.8, accuracy: 0.011)
        XCTAssertEqual(g.longitudes[2], 140.7, accuracy: 0.011)
        XCTAssertEqual(g.latitudes.last! - g.latitudes.first!, 80 / 111.32, accuracy: 0.02)
        XCTAssertTrue(g.latitudes == g.latitudes.sorted())
    }

    func testURLs() {
        let u = OpenMeteoGrid.weatherURL(latitudes: [41.0, 42.0], longitudes: [140.0, 141.0], forecastDays: 2)
        let s = u.absoluteString
        XCTAssertTrue(s.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        XCTAssertTrue(s.contains("latitude=41.00,41.00,42.00,42.00"), s)
        XCTAssertTrue(s.contains("longitude=140.00,141.00,140.00,141.00"), s)
        XCTAssertTrue(s.contains("wind_speed_unit=ms"))
        XCTAssertTrue(s.contains("forecast_days=2"))
        for f in ["cape", "visibility", "snowfall", "snow_depth", "uv_index", "cloud_cover_low"] { XCTAssertTrue(s.contains(f), f) }
        let m = OpenMeteoGrid.marineURL(latitudes: [41.0], longitudes: [140.0]).absoluteString
        XCTAssertTrue(m.hasPrefix("https://marine-api.open-meteo.com/v1/marine?"))
        XCTAssertTrue(m.contains("ocean_current_direction"))
        for f in ["sea_level_height_msl", "wind_wave_direction", "secondary_swell_wave_height"] { XCTAssertTrue(m.contains(f), f) }
        // 全変数に取得元の名前がある
        let mapped = Set(OpenMeteoGrid.weatherMap.values).union(OpenMeteoGrid.marineMap.values)
        XCTAssertEqual(mapped, Set(GridForecast.Variable.allCases))
        XCTAssertEqual(Set(OpenMeteoGrid.weatherMap.keys), Set(OpenMeteoGrid.weatherFields))
        XCTAssertEqual(Set(OpenMeteoGrid.marineMap.keys), Set(OpenMeteoGrid.marineFields))
    }

    func testSampleBilinearAndTime() {
        let g = makeGrid()
        // 中央：空間平均 3、時刻 0
        XCTAssertEqual(g.sample(.windSpeed, at: Coordinate(latitude: 41.5, longitude: 140.5), time: t0)!, 3, accuracy: 1e-9)
        // 西端：2、30 分後は +0.5
        XCTAssertEqual(g.sample(.windSpeed, at: Coordinate(latitude: 41.5, longitude: 140.0), time: t0.addingTimeInterval(1800))!, 2.5, accuracy: 1e-9)
        // 東端・1 時間後：5
        XCTAssertEqual(g.sample(.windSpeed, at: Coordinate(latitude: 42.0, longitude: 141.0), time: t0.addingTimeInterval(7200))!, 5, accuracy: 1e-9)
        // 範囲外
        XCTAssertNil(g.sample(.windSpeed, at: Coordinate(latitude: 43, longitude: 140.5), time: t0))
        // nil の隅は重みから外す：水温は東側が陸でも 10
        XCTAssertEqual(g.sample(.seaSurfaceTemperature, at: Coordinate(latitude: 41.5, longitude: 140.9), time: t0)!, 10, accuracy: 1e-9)
    }

    func testDirectionInterpolatesAcrossNorth() {
        let g = makeGrid()
        // 350° と 10° の中間は 0°（180° ではない）
        let d = g.sample(.windDirection, at: Coordinate(latitude: 41.5, longitude: 140.5), time: t0)!
        XCTAssertTrue(d < 1 || d > 359, "\(d)")
        let v = g.vector(speed: .windSpeed, direction: .windDirection, at: Coordinate(latitude: 41.5, longitude: 140.5), time: t0, from: true)!
        // 北風（北から吹く）→ 南向き：v は負、u はほぼ 0
        XCTAssertLessThan(v.v, -2.9)
        XCTAssertEqual(v.u, 0, accuracy: 0.1)
        let c = g.vector(speed: .windSpeed, direction: .windDirection, at: Coordinate(latitude: 41.5, longitude: 140.5), time: t0, from: false)!
        XCTAssertGreaterThan(c.v, 2.9)
    }

    func testDecodeMultiPoint() throws {
        let json = """
        [
         {"latitude":41.0,"longitude":140.0,"hourly":{"time":[1762300800,1762304400],"wind_speed_10m":[2,3],"wind_direction_10m":[350,350],"ocean_current_velocity":[3.6,7.2],"cape":[120,0],"visibility":[24140,800]}},
         {"latitude":41.0,"longitude":141.0,"hourly":{"time":[1762300800,1762304400],"wind_speed_10m":[4,5],"wind_direction_10m":[10,10],"ocean_current_velocity":[null,null]}}
        ]
        """
        let g = try OpenMeteoGrid.decode(Data(json.utf8), latitudes: [41.0], longitudes: [140.0, 141.0], fetchedAt: t0)
        XCTAssertEqual(g.times.count, 2)
        XCTAssertEqual(g.value(.windSpeed, timeIndex: 1, row: 0, col: 1), 5)
        XCTAssertEqual(g.value(.currentSpeed, timeIndex: 0, row: 0, col: 0)!, 1.0, accuracy: 1e-9)
        XCTAssertNil(g.value(.currentSpeed, timeIndex: 0, row: 0, col: 1))
        XCTAssertEqual(g.value(.cape, timeIndex: 0, row: 0, col: 0), 120)
        XCTAssertEqual(g.value(.visibility, timeIndex: 1, row: 0, col: 0), 800)
        XCTAssertNil(g.value(.cape, timeIndex: 0, row: 0, col: 1))
        XCTAssertEqual(g.range(of: .windSpeed), 2...5)
        XCTAssertThrowsError(try OpenMeteoGrid.decode(Data(json.utf8), latitudes: [41.0, 42.0], longitudes: [140.0, 141.0]))
        XCTAssertThrowsError(try OpenMeteoGrid.decode(Data("{\"error\":true,\"reason\":\"bad\"}".utf8), latitudes: [41.0], longitudes: [140.0]))
        let rt = try FogJSON.decode(GridForecast.self, from: try FogJSON.encode(g))
        XCTAssertEqual(rt, g)
    }
}
