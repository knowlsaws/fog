import Foundation

/// 月齢の簡易計算（既知の新月からの経過日数）。L2 で日の出入り・月の出入りの本実装に置き換える。
public enum MoonPhase {
    public static let synodicMonth = 29.530588853
    /// 基準新月: 2000-01-06 18:14 UTC
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    public static func age(at date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    /// 0=新月, 0.5=満月 の割合
    public static func fraction(at date: Date) -> Double { age(at: date) / synodicMonth }
}
