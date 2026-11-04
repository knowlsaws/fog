import Foundation

/// 潮名（大潮・中潮・小潮・長潮・若潮）。旧暦の日（月齢ベース）から決める一般的な区分。
public enum TideName: String, CaseIterable, Sendable {
    case spring = "大潮", middle = "中潮", neap = "小潮", long = "長潮", young = "若潮"

    /// 月齢（0〜29.53）から潮名を返す。
    public static func from(moonAge: Double) -> TideName {
        let age = moonAge.truncatingRemainder(dividingBy: 29.530588)
        let day = Int(age.rounded(.down)) + 1 // 旧暦の日に相当（1始まり）
        switch day {
        case 1...3, 15...18, 29, 30: return .spring
        case 4...6, 19...21: return .middle
        case 7...9, 22...24: return .neap
        case 10, 25: return .long
        case 11, 26: return .young
        default: return .middle
        }
    }
}
