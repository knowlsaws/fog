import Foundation

/// ユリウス日まわりの補助（天文計算・潮汐の天文引数で共用）。
enum JulianDay {
    /// J2000.0 (2000-01-01 12:00 TT ≈ UT) のユリウス日
    static let j2000: Double = 2_451_545.0

    /// Date（UTC）→ ユリウス日
    static func from(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    static func toDate(_ jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400)
    }

    /// J2000.0 からのユリウス世紀
    static func centuries(_ jd: Double) -> Double { (jd - j2000) / 36_525 }

    /// 0h UT からの経過（日）
    static func fractionOfDay(_ jd: Double) -> Double {
        let f = (jd + 0.5).truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }

    /// その日の 0h UT のユリウス日
    static func startOfUTCDay(_ jd: Double) -> Double { (jd + 0.5).rounded(.down) - 0.5 }
}

enum Angle {
    static func normalize(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
    static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    static func deg(_ rad: Double) -> Double { rad * 180 / .pi }
}

/// 地方時の「その日」を扱うための補助。日の出入りは地方時の暦日単位で求める。
enum LocalDay {
    /// 指定タイムゾーンでの暦日の 0 時（UTC の Date）
    static func start(of date: Date, in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.startOfDay(for: date)
    }
}
