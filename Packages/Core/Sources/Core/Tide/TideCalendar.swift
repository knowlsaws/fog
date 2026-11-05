import Foundation

/// 日ごとの潮名の並び（遠征の下調べ・年間カレンダー用）。月齢から決めるので通信なし。
public enum TideCalendar {
    public struct Day: Hashable, Sendable {
        public var dayStart: Date
        public var tideName: TideName
        public var moonAge: Double
    }

    /// `from` の日から `days` 日分。各日は正午の月齢で潮名を決める。
    public static func days(from: Date, days: Int, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [Day] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let start = cal.startOfDay(for: from)
        return (0..<max(0, days)).map { i in
            let d = start.addingTimeInterval(Double(i) * 86_400)
            let age = MoonCalculator.age(at: d.addingTimeInterval(12 * 3600))
            return Day(dayStart: d, tideName: TideName.from(moonAge: age), moonAge: age)
        }
    }
}
