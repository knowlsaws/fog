import Foundation

/// 月の位置（Meeus「Astronomical Algorithms」第47章の主要項）、月齢、月の出入り。
/// 月齢は国立天文台と同じ定義：直前の朔（新月）からの経過日数。
public struct MoonTimes: Hashable, Sendable {
    public var moonrise: Date?
    public var moonset: Date?
}

public enum MoonCalculator {
    public static let synodicMonth = 29.530588853

    /// 月の黄経・黄緯・距離（度, 度, km）。
    static func position(jd: Double) -> (longitude: Double, latitude: Double, distanceKm: Double) {
        let t = JulianDay.centuries(jd)
        let lp = Angle.normalize(218.3164477 + 481267.88123421 * t - 0.0015786 * t * t + t * t * t / 538841 - t * t * t * t / 65194000)
        let d = Angle.normalize(297.8501921 + 445267.1114034 * t - 0.0018819 * t * t + t * t * t / 545868 - t * t * t * t / 113065000)
        let m = Angle.normalize(357.5291092 + 35999.0502909 * t - 0.0001536 * t * t + t * t * t / 24490000)
        let mp = Angle.normalize(134.9633964 + 477198.8675055 * t + 0.0087414 * t * t + t * t * t / 69699 - t * t * t * t / 14712000)
        let f = Angle.normalize(93.2720950 + 483202.0175233 * t - 0.0036539 * t * t - t * t * t / 3526000 + t * t * t * t / 863310000)
        let a1 = Angle.normalize(119.75 + 131.849 * t)
        let a2 = Angle.normalize(53.09 + 479264.290 * t)
        let a3 = Angle.normalize(313.45 + 481266.484 * t)
        let e = 1 - 0.002516 * t - 0.0000074 * t * t

        // (D, M, M', F, Σl 係数, Σr 係数)
        let lrTerms: [(Int, Int, Int, Int, Double, Double)] = [
            (0,0,1,0, 6288774, -20905355), (2,0,-1,0, 1274027, -3699111), (2,0,0,0, 658314, -2955968),
            (0,0,2,0, 213618, -569925), (0,1,0,0, -185116, 48888), (0,0,0,2, -114332, -3149),
            (2,0,-2,0, 58793, 246158), (2,-1,-1,0, 57066, -152138), (2,0,1,0, 53322, -170733),
            (2,-1,0,0, 45758, -204586), (0,1,-1,0, -40923, -129620), (1,0,0,0, -34720, 108743),
            (0,1,1,0, -30383, 104755), (2,0,0,-2, 15327, 10321), (0,0,1,2, -12528, 0),
            (0,0,1,-2, 10980, 79661), (4,0,-1,0, 10675, -34782), (0,0,3,0, 10034, -23210),
            (4,0,-2,0, 8548, -21636), (2,1,-1,0, -7888, 24208), (2,1,0,0, -6766, 30824),
            (1,0,-1,0, -5163, -8379), (1,1,0,0, 4987, -16675), (2,-1,1,0, 4036, -12831),
            (2,0,2,0, 3994, -10445), (4,0,0,0, 3861, -11650), (2,0,-3,0, 3665, 14403),
            (0,1,-2,0, -2689, -7003), (2,0,-1,2, -2602, 0), (2,-1,-2,0, 2390, 10056),
            (1,0,1,0, -2348, 6322), (2,-2,0,0, 2236, -9884), (0,1,2,0, -2120, 5751),
            (0,2,0,0, -2069, 0), (2,-2,-1,0, 2048, -4950), (2,0,1,-2, -1773, 4130),
            (2,0,0,2, -1595, 0), (4,-1,-1,0, 1215, -3958), (0,0,2,2, -1110, 0),
            (3,0,-1,0, -892, 3258), (2,1,1,0, -810, 2616), (4,-1,-2,0, 759, -1897),
            (0,2,-1,0, -713, -2117), (2,2,-1,0, -700, 2354), (2,1,-2,0, 691, 0),
            (2,-1,0,-2, 596, 0), (4,0,1,0, 549, -1423), (0,0,4,0, 537, -1117),
            (4,-1,0,0, 520, -1571), (1,0,-2,0, -487, -1739), (2,1,0,-2, -399, 0),
            (0,0,2,-2, -381, -4421), (1,1,1,0, 351, 0), (3,0,-2,0, -340, 0),
            (4,0,-3,0, 330, 0), (2,-1,2,0, 327, 0), (0,2,1,0, -323, 1165),
            (1,1,-1,0, 299, 0), (2,0,3,0, 294, 0), (2,0,-1,-2, 0, 8752),
        ]
        let bTerms: [(Int, Int, Int, Int, Double)] = [
            (0,0,0,1, 5128122), (0,0,1,1, 280602), (0,0,1,-1, 277693), (2,0,0,-1, 173237),
            (2,0,-1,1, 55413), (2,0,-1,-1, 46271), (2,0,0,1, 32573), (0,0,2,1, 17198),
            (2,0,1,-1, 9266), (0,0,2,-1, 8822), (2,-1,0,-1, 8216), (2,0,-2,-1, 4324),
            (2,0,1,1, 4200), (2,1,0,-1, -3359), (2,-1,-1,1, 2463), (2,-1,0,1, 2211),
            (2,-1,-1,-1, 2065), (0,1,-1,-1, -1870), (4,0,-1,-1, 1828), (0,1,0,1, -1794),
            (0,0,0,3, -1749), (0,1,-1,1, -1565), (1,0,0,1, -1491), (0,1,1,1, -1475),
            (0,1,1,-1, -1410), (0,1,0,-1, -1344), (1,0,0,-1, -1335), (0,0,3,1, 1107),
            (4,0,0,-1, 1021), (4,0,-1,1, 833), (0,0,1,-3, 777), (4,0,-2,1, 671),
            (2,0,0,-3, 607), (2,0,2,-1, 596), (2,-1,1,-1, 491), (2,0,-2,1, -451),
            (0,0,3,-1, 439), (2,0,2,1, 422), (2,0,-3,-1, 421), (2,1,-1,1, -366),
            (2,1,0,1, -351), (4,0,0,1, 331), (2,-1,1,1, 315), (2,-2,0,-1, 302),
            (0,0,1,3, -283), (2,1,1,-1, -229), (1,1,0,-1, 223), (1,1,0,1, 223),
            (0,1,-2,-1, -220), (2,1,-1,-1, -220), (1,0,1,1, -185), (2,-1,-2,-1, 181),
            (0,1,2,1, -177), (4,0,-2,-1, 176), (4,-1,-1,-1, 166), (1,0,1,-1, -164),
            (4,0,1,-1, 132), (1,0,-1,-1, -119), (4,-1,0,-1, 115), (2,-2,0,1, 107),
        ]
        var sumL = 0.0, sumR = 0.0, sumB = 0.0
        for (cd, cm, cmp, cf, l, r) in lrTerms {
            let arg = Angle.rad(Double(cd) * d + Double(cm) * m + Double(cmp) * mp + Double(cf) * f)
            let ef = abs(cm) == 1 ? e : (abs(cm) == 2 ? e * e : 1)
            sumL += l * ef * sin(arg)
            sumR += r * ef * cos(arg)
        }
        for (cd, cm, cmp, cf, b) in bTerms {
            let arg = Angle.rad(Double(cd) * d + Double(cm) * m + Double(cmp) * mp + Double(cf) * f)
            let ef = abs(cm) == 1 ? e : (abs(cm) == 2 ? e * e : 1)
            sumB += b * ef * sin(arg)
        }
        sumL += 3958 * sin(Angle.rad(a1)) + 1962 * sin(Angle.rad(lp - f)) + 318 * sin(Angle.rad(a2))
        sumB += -2235 * sin(Angle.rad(lp)) + 382 * sin(Angle.rad(a3)) + 175 * sin(Angle.rad(a1 - f))
            + 175 * sin(Angle.rad(a1 + f)) + 127 * sin(Angle.rad(lp - mp)) - 115 * sin(Angle.rad(lp + mp))
        let longitude = Angle.normalize(lp + sumL / 1_000_000)
        let latitude = sumB / 1_000_000
        let distance = 385_000.56 + sumR / 1000
        return (longitude, latitude, distance)
    }

    /// 太陽と月の黄経差（0〜360°）。0 が朔、180 が望。
    public static func elongation(at date: Date) -> Double {
        let jd = JulianDay.from(date)
        let moon = position(jd: jd).longitude
        let sun = SunCalculator.apparentLongitude(jd: jd)
        return Angle.normalize(moon - sun)
    }

    /// 直前の朔の時刻（黄経差が 0 になる時刻を二分法で探す）。
    public static func lastNewMoon(before date: Date) -> Date {
        // 平均朔望月で当たりを付け、黄経差が 0 を跨ぐ区間を挟む
        var hi = date
        var eHi = elongation(at: hi)
        var lo = hi.addingTimeInterval(-eHi / 360 * synodicMonth * 86_400 - 2 * 86_400)
        var eLo = elongation(at: lo)
        // lo 側は 0 のすぐ手前（≈ 330〜360°）、hi 側は小さな角のはず。そうでなければ区間をずらす
        var guardCount = 0
        while !(eLo > 180 && eHi < 180) && guardCount < 10 {
            if eLo <= 180 { lo = lo.addingTimeInterval(-2 * 86_400); eLo = elongation(at: lo) }
            if eHi >= 180 { hi = hi.addingTimeInterval(-2 * 86_400); eHi = elongation(at: hi) }
            guardCount += 1
        }
        for _ in 0..<40 {
            let mid = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            let eMid = elongation(at: mid)
            if eMid > 180 { lo = mid } else { hi = mid }
            if hi.timeIntervalSince(lo) < 1 { break }
        }
        return hi
    }

    /// 月齢（直前の朔からの日数）。
    public static func age(at date: Date) -> Double {
        date.timeIntervalSince(lastNewMoon(before: date)) / 86_400
    }

    /// 輝面比（0〜1）。
    public static func illuminatedFraction(at date: Date) -> Double {
        let e = Angle.rad(elongation(at: date))
        return (1 - cos(e)) / 2
    }

    /// 月の赤経・赤緯（度）。
    static func equatorial(jd: Double) -> (ra: Double, dec: Double) {
        let p = position(jd: jd)
        let t = JulianDay.centuries(jd)
        let eps = Angle.rad(23.439291 - 0.0130042 * t)
        let lon = Angle.rad(p.longitude), lat = Angle.rad(p.latitude)
        let ra = atan2(sin(lon) * cos(eps) - tan(lat) * sin(eps), cos(lon))
        let dec = asin(sin(lat) * cos(eps) + cos(lat) * sin(eps) * sin(lon))
        return (Angle.normalize(Angle.deg(ra)), Angle.deg(dec))
    }

    /// 月の高度（度、地心・視差補正込みの簡易）。
    public static func altitude(at date: Date, coordinate: Coordinate) -> Double {
        let jd = JulianDay.from(date)
        let eq = equatorial(jd: jd)
        let t = JulianDay.centuries(jd)
        let gmst = Angle.normalize(280.46061837 + 360.98564736629 * (jd - JulianDay.j2000) + 0.000387933 * t * t)
        let lst = Angle.normalize(gmst + coordinate.longitude)
        let ha = Angle.rad(Angle.normalize(lst - eq.ra))
        let lat = Angle.rad(coordinate.latitude), dec = Angle.rad(eq.dec)
        let alt = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha))
        // 地平視差（約 0.95°）を引き、月半径と屈折（0.57°）を考慮した出入りの基準は呼び出し側で
        let distance = position(jd: jd).distanceKm
        let parallax = Angle.deg(asin(6378.14 / distance))
        return Angle.deg(alt) - parallax * cos(alt)
    }

    /// 指定日（タイムゾーンの暦日）の月の出入り。出入りの基準高度は −0.583°（屈折 0.567° + 半径を視差で相殺した慣例値）。
    public static func times(on date: Date, at coordinate: Coordinate, timeZone: TimeZone) -> MoonTimes {
        let start = LocalDay.start(of: date, in: timeZone)
        let threshold = -0.583
        var rise: Date?, set: Date?
        let step: TimeInterval = 600
        var prev = altitude(at: start, coordinate: coordinate) - threshold
        var t = start
        while t < start.addingTimeInterval(86_400) {
            let next = t.addingTimeInterval(step)
            let cur = altitude(at: next, coordinate: coordinate) - threshold
            if prev < 0 && cur >= 0 && rise == nil {
                rise = bisect(from: t, to: next, coordinate: coordinate, threshold: threshold)
            } else if prev >= 0 && cur < 0 && set == nil {
                set = bisect(from: t, to: next, coordinate: coordinate, threshold: threshold)
            }
            prev = cur
            t = next
        }
        return MoonTimes(moonrise: rise, moonset: set)
    }

    private static func bisect(from: Date, to: Date, coordinate: Coordinate, threshold: Double) -> Date {
        var lo = from, hi = to
        let loSign = (altitude(at: lo, coordinate: coordinate) - threshold) < 0
        for _ in 0..<20 {
            let mid = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            let midNeg = (altitude(at: mid, coordinate: coordinate) - threshold) < 0
            if midNeg == loSign { lo = mid } else { hi = mid }
        }
        return hi
    }
}

/// 互換 API（L0 の簡易実装を置き換え）。
public enum MoonPhase {
    public static let synodicMonth = MoonCalculator.synodicMonth
    public static func age(at date: Date) -> Double { MoonCalculator.age(at: date) }
    /// 0=新月, 0.5=満月 の割合
    public static func fraction(at date: Date) -> Double { MoonCalculator.elongation(at: date) / 360 }
}
