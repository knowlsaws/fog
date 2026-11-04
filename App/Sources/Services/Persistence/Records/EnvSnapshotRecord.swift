import Foundation
import SwiftData
import Core

/// `Core.EnvSnapshot`（釣行中の定期スナップショット）の SwiftData 表現。
/// 分析で時系列に引くため、釣果に埋め込む環境とは別に1行ずつ持つ。
@Model
final class EnvSnapshotRecord {
    var uuid: UUID = UUID()
    var at: Date = Date()
    var latitude: Double = 0
    var longitude: Double = 0

    var airTemperatureC: Double? = nil
    var humidity: Double? = nil
    var conditionCode: String? = nil
    var windSpeedMS: Double? = nil
    var windGustMS: Double? = nil
    var windDirectionDeg: Double? = nil
    var pressureHPa: Double? = nil
    var cloudCover: Double? = nil
    var precipitationMM: Double? = nil
    var visibilityM: Double? = nil

    var measuredPressureHPa: Double? = nil
    var pressureTrend3hHPa: Double? = nil

    var tideLevelCm: Double? = nil
    var tideRateCmPerHour: Double? = nil
    var tideName: String? = nil
    var nextHighTideAt: Date? = nil
    var nextLowTideAt: Date? = nil

    var waveHeightM: Double? = nil
    var wavePeriodS: Double? = nil
    var waveDirectionDeg: Double? = nil
    var swellHeightM: Double? = nil
    var seaSurfaceTempC: Double? = nil
    var oceanCurrentMS: Double? = nil

    var sunriseAt: Date? = nil
    var sunsetAt: Date? = nil
    var moonAge: Double? = nil

    var isForecast: Bool = false

    var session: SessionRecord? = nil

    init(core: EnvSnapshot, session: SessionRecord?) {
        uuid = core.id
        self.session = session
        apply(core)
    }

    func apply(_ e: EnvSnapshot) {
        at = e.at
        latitude = e.coordinate.latitude
        longitude = e.coordinate.longitude
        airTemperatureC = e.airTemperatureC
        humidity = e.humidity
        conditionCode = e.conditionCode
        windSpeedMS = e.windSpeedMS
        windGustMS = e.windGustMS
        windDirectionDeg = e.windDirectionDeg
        pressureHPa = e.pressureHPa
        cloudCover = e.cloudCover
        precipitationMM = e.precipitationMM
        visibilityM = e.visibilityM
        measuredPressureHPa = e.measuredPressureHPa
        pressureTrend3hHPa = e.pressureTrend3hHPa
        tideLevelCm = e.tideLevelCm
        tideRateCmPerHour = e.tideRateCmPerHour
        tideName = e.tideName
        nextHighTideAt = e.nextHighTideAt
        nextLowTideAt = e.nextLowTideAt
        waveHeightM = e.waveHeightM
        wavePeriodS = e.wavePeriodS
        waveDirectionDeg = e.waveDirectionDeg
        swellHeightM = e.swellHeightM
        seaSurfaceTempC = e.seaSurfaceTempC
        oceanCurrentMS = e.oceanCurrentMS
        sunriseAt = e.sunriseAt
        sunsetAt = e.sunsetAt
        moonAge = e.moonAge
        isForecast = e.isForecast
    }

    var core: EnvSnapshot {
        var e = EnvSnapshot(id: uuid, at: at, coordinate: Coordinate(latitude: latitude, longitude: longitude), isForecast: isForecast)
        e.airTemperatureC = airTemperatureC
        e.humidity = humidity
        e.conditionCode = conditionCode
        e.windSpeedMS = windSpeedMS
        e.windGustMS = windGustMS
        e.windDirectionDeg = windDirectionDeg
        e.pressureHPa = pressureHPa
        e.cloudCover = cloudCover
        e.precipitationMM = precipitationMM
        e.visibilityM = visibilityM
        e.measuredPressureHPa = measuredPressureHPa
        e.pressureTrend3hHPa = pressureTrend3hHPa
        e.tideLevelCm = tideLevelCm
        e.tideRateCmPerHour = tideRateCmPerHour
        e.tideName = tideName
        e.nextHighTideAt = nextHighTideAt
        e.nextLowTideAt = nextLowTideAt
        e.waveHeightM = waveHeightM
        e.wavePeriodS = wavePeriodS
        e.waveDirectionDeg = waveDirectionDeg
        e.swellHeightM = swellHeightM
        e.seaSurfaceTempC = seaSurfaceTempC
        e.oceanCurrentMS = oceanCurrentMS
        e.sunriseAt = sunriseAt
        e.sunsetAt = sunsetAt
        e.moonAge = moonAge
        return e
    }
}
