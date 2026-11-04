import Foundation
import CoreLocation
import WeatherKit
import Core

/// 気象の取得元。テストではモックに差し替える。
protocol WeatherProviding: Sendable {
    /// 現在値と、`from`〜`to` の時間別値（WeatherKit は過去も約 10 日先も返す）。
    func fetch(at coordinate: Coordinate, from: Date, to: Date) async throws -> [WeatherSample]
}

/// WeatherKit（Apple 公式）。端末から直接取得し、位置は 0.01° に丸めて送る。
struct WeatherKitProvider: WeatherProviding {
    func fetch(at coordinate: Coordinate, from: Date, to: Date) async throws -> [WeatherSample] {
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lon = (coordinate.longitude * 100).rounded() / 100
        let location = CLLocation(latitude: lat, longitude: lon)
        let now = Date()
        let (current, hourly) = try await WeatherService.shared.weather(for: location, including: .current, .hourly(startDate: from, endDate: to))
        var samples: [WeatherSample] = hourly.forecast.map { h in
            var s = WeatherSample(at: h.date, isForecast: h.date > now.addingTimeInterval(-3600))
            s.airTemperatureC = h.temperature.converted(to: .celsius).value
            s.humidity = h.humidity
            s.conditionCode = h.condition.rawValue
            s.windSpeedMS = h.wind.speed.converted(to: .metersPerSecond).value
            s.windGustMS = h.wind.gust?.converted(to: .metersPerSecond).value
            s.windDirectionDeg = h.wind.direction.converted(to: .degrees).value
            s.pressureHPa = h.pressure.converted(to: .hectopascals).value
            s.cloudCover = h.cloudCover
            s.precipitationMM = h.precipitationAmount.converted(to: .millimeters).value
            s.visibilityM = h.visibility.converted(to: .meters).value
            return s
        }
        var c = WeatherSample(at: current.date, isForecast: false)
        c.airTemperatureC = current.temperature.converted(to: .celsius).value
        c.humidity = current.humidity
        c.conditionCode = current.condition.rawValue
        c.windSpeedMS = current.wind.speed.converted(to: .metersPerSecond).value
        c.windGustMS = current.wind.gust?.converted(to: .metersPerSecond).value
        c.windDirectionDeg = current.wind.direction.converted(to: .degrees).value
        c.pressureHPa = current.pressure.converted(to: .hectopascals).value
        c.cloudCover = current.cloudCover
        c.visibilityM = current.visibility.converted(to: .meters).value
        samples.append(c)
        return samples
    }

    /// 設定画面に出す Apple Weather の帰属表示。
    static func attribution() async -> (serviceName: String, legalURL: URL)? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return (a.serviceName, a.legalPageURL)
    }
}
