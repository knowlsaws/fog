import Foundation

/// 太陽の出入りと薄明（NOAA の太陽位置アルゴリズム。日の出入りで ±1 分程度）。
public struct SunTimes: Hashable, Sendable {
    /// 市民薄明の始まり（朝マズメの始まり）
    public var civilDawn: Date?
    public var sunrise: Date?
    public var solarNoon: Date
    public var sunset: Date?
    /// 市民薄明の終わり（夕マズメの終わり）
    public var civilDusk: Date?
}

public enum SunCalculator {
    /// 地平線の屈折と太陽半径ぶん：日の出入りは高度 −0.833°
    public static let sunriseAltitude = -0.833
    /// 市民薄明は高度 −6°
    public static let civilTwilightAltitude = -6.0

    /// 指定日（タイムゾーンの暦日）の出入り時刻。
    public static func times(on date: Date, at coordinate: Coordinate, timeZone: TimeZone) -> SunTimes {
        let dayStart = LocalDay.start(of: date, in: timeZone)
        let noonGuess = dayStart.addingTimeInterval(12 * 3600 + Double(timeZone.secondsFromGMT(for: dayStart)) - coordinate.longitude * 240)
        // 太陽正中の UTC：経度 1° = 4 分。均時差で補正
        let solarNoon = noonGuess.addingTimeInterval(-equationOfTimeMinutes(at: noonGuess) * 60)
        func event(altitude: Double, rising: Bool) -> Date? {
            // 正中時刻の赤緯・均時差で時角を求め、1回反復して精度を上げる
            var t = solarNoon
            for _ in 0..<2 {
                guard let ha = hourAngle(altitude: altitude, latitude: coordinate.latitude, at: t) else { return nil }
                let minutes = ha * 4 // 時角 1° = 4 分
                t = solarNoon.addingTimeInterval((rising ? -minutes : minutes) * 60)
            }
            return t
        }
        return SunTimes(
            civilDawn: event(altitude: civilTwilightAltitude, rising: true),
            sunrise: event(altitude: sunriseAltitude, rising: true),
            solarNoon: solarNoon,
            sunset: event(altitude: sunriseAltitude, rising: false),
            civilDusk: event(altitude: civilTwilightAltitude, rising: false)
        )
    }

    /// 太陽高度（度）。
    public static func altitude(at date: Date, coordinate: Coordinate) -> Double {
        let jd = JulianDay.from(date)
        let (dec, eot) = declinationAndEquationOfTime(jd: jd)
        let minutesUTC = JulianDay.fractionOfDay(jd) * 1440
        let trueSolarMinutes = (minutesUTC + eot + 4 * coordinate.longitude).truncatingRemainder(dividingBy: 1440)
        var ha = trueSolarMinutes / 4 - 180
        if ha < -180 { ha += 360 }
        let lat = Angle.rad(coordinate.latitude), d = Angle.rad(dec)
        let cosZenith = sin(lat) * sin(d) + cos(lat) * cos(d) * cos(Angle.rad(ha))
        return 90 - Angle.deg(acos(max(-1, min(1, cosZenith))))
    }

    // MARK: 内部

    static func equationOfTimeMinutes(at date: Date) -> Double {
        declinationAndEquationOfTime(jd: JulianDay.from(date)).eot
    }

    /// 指定高度になる時角（度）。極夜・白夜なら nil。
    static func hourAngle(altitude: Double, latitude: Double, at date: Date) -> Double? {
        let dec = declinationAndEquationOfTime(jd: JulianDay.from(date)).declination
        let lat = Angle.rad(latitude), d = Angle.rad(dec), h = Angle.rad(altitude)
        let cosHA = (sin(h) - sin(lat) * sin(d)) / (cos(lat) * cos(d))
        guard cosHA >= -1, cosHA <= 1 else { return nil }
        return Angle.deg(acos(cosHA))
    }

    /// NOAA: 赤緯（度）と均時差（分）
    static func declinationAndEquationOfTime(jd: Double) -> (declination: Double, eot: Double) {
        let t = JulianDay.centuries(jd)
        let l0 = Angle.normalize(280.46646 + t * (36000.76983 + t * 0.0003032))
        let m = Angle.normalize(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mr = Angle.rad(m)
        let c = sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * mr) * (0.019993 - 0.000101 * t) + sin(3 * mr) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let apparentLong = trueLong - 0.00569 - 0.00478 * sin(Angle.rad(omega))
        let e0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = e0 + 0.00256 * cos(Angle.rad(omega))
        let declination = Angle.deg(asin(sin(Angle.rad(obliquity)) * sin(Angle.rad(apparentLong))))
        let y = pow(tan(Angle.rad(obliquity / 2)), 2)
        let l0r = Angle.rad(l0)
        let eot = Angle.deg(y * sin(2 * l0r) - 2 * e * sin(mr) + 4 * e * y * sin(mr) * cos(2 * l0r)
                            - 0.5 * y * y * sin(4 * l0r) - 1.25 * e * e * sin(2 * mr)) * 4
        return (declination, eot)
    }

    /// 太陽の平均黄経（度）。月齢計算で使う（視黄経は月の計算側で求める）。
    static func apparentLongitude(jd: Double) -> Double {
        let t = JulianDay.centuries(jd)
        let l0 = 280.46646 + t * (36000.76983 + t * 0.0003032)
        let m = Angle.rad(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let c = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m) * (0.019993 - 0.000101 * t) + sin(3 * m) * 0.000289
        let omega = Angle.rad(125.04 - 1934.136 * t)
        return Angle.normalize(l0 + c - 0.00569 - 0.00478 * sin(omega))
    }
}
