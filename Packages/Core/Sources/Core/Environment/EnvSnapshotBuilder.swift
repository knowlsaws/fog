import Foundation

/// §2 の全項目を、キャッシュ済みデータと端末内計算だけで組み立てる（通信しない）。
/// 気象・海況はキャッシュから補間、気圧は端末実測、潮汐・天文は Core で計算する。
public struct EnvSnapshotBuilder: Sendable {
    public var tideStation: TideStation?
    public var timeZone: TimeZone

    public init(tideStation: TideStation?, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        self.tideStation = tideStation
        self.timeZone = timeZone
    }

    public struct Inputs: Sendable {
        public var weather: [WeatherSample]
        public var marine: [MarineSample]
        public var pressure: [PressureSample]
        public init(weather: [WeatherSample] = [], marine: [MarineSample] = [], pressure: [PressureSample] = []) {
            self.weather = weather; self.marine = marine; self.pressure = pressure
        }
    }

    public func build(at date: Date, coordinate: Coordinate, inputs: Inputs) -> EnvSnapshot {
        build(at: date, coordinate: coordinate, inputs: inputs, tide: tideStation.map { TideEngine(station: $0) }, extremes: nil)
    }

    /// 推移計算用：潮汐エンジンと期間内の満干を渡すと、点ごとの満干探索を省ける（ホームの 15 分刻み）。
    public func build(at date: Date, coordinate: Coordinate, inputs: Inputs, tide: TideEngine?, extremes: [TideExtreme]?) -> EnvSnapshot {
        var env = EnvSnapshot(at: date, coordinate: coordinate, isForecast: false)

        // 気象：直近 1 時間値を補間
        func w(_ key: (WeatherSample) -> Double?) -> Double? {
            Series.interpolate(inputs.weather.compactMap { s in key(s).map { (s.at, $0) } }, at: date)
        }
        env.airTemperatureC = w(\.airTemperatureC)
        env.humidity = w(\.humidity)
        env.windSpeedMS = w(\.windSpeedMS)
        env.windGustMS = w(\.windGustMS)
        env.pressureHPa = w(\.pressureHPa)
        env.cloudCover = w(\.cloudCover)
        env.precipitationMM = w(\.precipitationMM)
        env.precipitationChance = w(\.precipitationChance)
        env.visibilityM = w(\.visibilityM)
        if let nearest = Series.nearest(inputs.weather, at: date, time: \.at) {
            env.conditionCode = nearest.conditionCode
            env.windDirectionDeg = nearest.windDirectionDeg
            env.isForecast = nearest.isForecast
        } else {
            env.isForecast = true
        }

        // 気圧（実測）と傾向
        if let latest = inputs.pressure.filter({ $0.at <= date }).max(by: { $0.at < $1.at }),
           date.timeIntervalSince(latest.at) < 3600 {
            env.measuredPressureHPa = latest.pressureHPa
        }
        env.pressureTrend3hHPa = PressureTrend.threeHourChange(inputs.pressure, now: date)
            ?? forecastPressureTrend(inputs.weather, at: date)

        // 海況
        func m(_ key: (MarineSample) -> Double?) -> Double? {
            Series.interpolate(inputs.marine.compactMap { s in key(s).map { (s.at, $0) } }, at: date)
        }
        env.waveHeightM = m(\.waveHeightM)
        env.wavePeriodS = m(\.wavePeriodS)
        env.waveDirectionDeg = Series.nearest(inputs.marine, at: date, time: \.at)?.waveDirectionDeg
        env.swellHeightM = m(\.swellHeightM)
        env.seaSurfaceTempC = m(\.seaSurfaceTempC)
        env.oceanCurrentMS = m(\.oceanCurrentMS)

        // 潮汐
        if let engine = tide {
            env.tideLevelCm = engine.level(at: date)
            env.tideRateCmPerHour = engine.rate(at: date)
            let next: [TideExtreme]
            if let extremes, let lastKnown = extremes.last?.at, lastKnown > date.addingTimeInterval(13 * 3600) {
                next = extremes.filter { $0.at > date }
            } else {
                next = engine.nextExtremes(after: date, count: 2)
            }
            env.nextHighTideAt = next.first { $0.kind == .high }?.at
            env.nextLowTideAt = next.first { $0.kind == .low }?.at
        }
        env.tideName = TideName.from(moonAge: MoonCalculator.age(at: date)).rawValue

        // 天文
        let sun = SunCalculator.times(on: date, at: coordinate, timeZone: timeZone)
        env.sunriseAt = sun.sunrise
        env.sunsetAt = sun.sunset
        env.moonAge = MoonCalculator.age(at: date)
        return env
    }

    /// 実測が無いときは予報の気圧から 3 時間傾向を出す。
    func forecastPressureTrend(_ weather: [WeatherSample], at date: Date) -> Double? {
        let series = weather.compactMap { s in s.pressureHPa.map { (s.at, $0) } }
        guard let now = Series.interpolate(series, at: date),
              let before = Series.interpolate(series, at: date.addingTimeInterval(-3 * 3600)) else { return nil }
        return now - before
    }

    /// 実況値が取れたら、予報で埋めたスナップショットの気象項目を差し替える（F-06）。
    public func replacingForecast(in snapshot: EnvSnapshot, with observations: [WeatherSample]) -> EnvSnapshot {
        guard snapshot.isForecast, let obs = Series.nearest(observations.filter { !$0.isForecast }, at: snapshot.at, time: \.at, maxGap: 1800) else {
            return snapshot
        }
        var s = snapshot
        s.airTemperatureC = obs.airTemperatureC ?? s.airTemperatureC
        s.humidity = obs.humidity ?? s.humidity
        s.conditionCode = obs.conditionCode ?? s.conditionCode
        s.windSpeedMS = obs.windSpeedMS ?? s.windSpeedMS
        s.windGustMS = obs.windGustMS ?? s.windGustMS
        s.windDirectionDeg = obs.windDirectionDeg ?? s.windDirectionDeg
        s.pressureHPa = obs.pressureHPa ?? s.pressureHPa
        s.cloudCover = obs.cloudCover ?? s.cloudCover
        s.precipitationMM = obs.precipitationMM ?? s.precipitationMM
        s.visibilityM = obs.visibilityM ?? s.visibilityM
        s.isForecast = false
        return s
    }
}
