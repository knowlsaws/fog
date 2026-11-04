import Foundation

/// 日本の祝日（国民の祝日に関する法律）。2000 年以降の規則に従う純粋な日付計算。
/// 振替休日と国民の休日も含む。年月日は日本時間の暦日として扱う（タイムゾーンは呼び出し側で解決する）。
public enum JapaneseHolidays {
    /// その日が祝日（振替休日・国民の休日を含む）なら true
    public static func isHoliday(year: Int, month: Int, day: Int) -> Bool {
        if fixedOrRuleBased(year: year, month: month, day: day) { return true }
        if isSubstitute(year: year, month: month, day: day) { return true }
        return isCitizensHoliday(year: year, month: month, day: day)
    }

    /// 祝日の名前。祝日でなければ nil
    public static func name(year: Int, month: Int, day: Int) -> String? {
        if let n = ruleName(year: year, month: month, day: day) { return n }
        if isSubstitute(year: year, month: month, day: day) { return "振替休日" }
        if isCitizensHoliday(year: year, month: month, day: day) { return "国民の休日" }
        return nil
    }

    // MARK: - 規則

    private static func fixedOrRuleBased(year: Int, month: Int, day: Int) -> Bool {
        ruleName(year: year, month: month, day: day) != nil
    }

    private static func ruleName(year: Int, month: Int, day: Int) -> String? {
        guard year >= 2000 else { return nil }
        switch (month, day) {
        case (1, 1): return "元日"
        case (2, 11): return "建国記念の日"
        case (2, 23) where year >= 2020: return "天皇誕生日"
        case (12, 23) where year <= 2018: return "天皇誕生日"
        case (4, 29): return "昭和の日"
        case (5, 3): return "憲法記念日"
        case (5, 4) where year >= 2007: return "みどりの日"
        case (5, 5): return "こどもの日"
        case (8, 11) where year >= 2016 && year != 2020 && year != 2021: return "山の日"
        case (11, 3): return "文化の日"
        case (11, 23): return "勤労感謝の日"
        default: break
        }
        // 月曜に固定された祝日（ハッピーマンデー）
        if month == 1, day == nthMonday(2, year: year, month: 1) { return "成人の日" }
        if month == 7, year != 2020, year != 2021, day == nthMonday(3, year: year, month: 7) { return "海の日" }
        if month == 9, day == nthMonday(3, year: year, month: 9) { return "敬老の日" }
        if month == 10, year != 2020, year != 2021, day == nthMonday(2, year: year, month: 10) {
            return year >= 2020 ? "スポーツの日" : "体育の日"
        }
        // 春分・秋分（簡易式。1980〜2099 年で有効）
        if month == 3, day == vernalEquinoxDay(year) { return "春分の日" }
        if month == 9, day == autumnalEquinoxDay(year) { return "秋分の日" }
        // 東京 2020 の特例
        if year == 2020 {
            if (month, day) == (7, 23) { return "海の日" }
            if (month, day) == (7, 24) { return "スポーツの日" }
            if (month, day) == (8, 10) { return "山の日" }
        }
        if year == 2021 {
            if (month, day) == (7, 22) { return "海の日" }
            if (month, day) == (7, 23) { return "スポーツの日" }
            if (month, day) == (8, 8) { return "山の日" }
        }
        // 2019 年の皇位継承
        if year == 2019 {
            if (month, day) == (5, 1) { return "天皇の即位の日" }
            if (month, day) == (10, 22) { return "即位礼正殿の儀" }
        }
        return nil
    }

    /// 振替休日：祝日が日曜なら、その後の最初の「祝日でない日」が休み
    private static func isSubstitute(year: Int, month: Int, day: Int) -> Bool {
        // 直前の数日を遡って、日曜の祝日からこの日まで祝日が連続しているか
        var d = ordinal(year: year, month: month, day: day) - 1
        var steps = 0
        while steps < 7 {
            let (y, m, dd) = civil(ordinal: d)
            guard fixedOrRuleBased(year: y, month: m, day: dd) else { return false }
            if weekday(year: y, month: m, day: dd) == 1 { return true }
            d -= 1; steps += 1
        }
        return false
    }

    /// 国民の休日：前日と翌日が祝日で、その日が日曜でも祝日でもない
    private static func isCitizensHoliday(year: Int, month: Int, day: Int) -> Bool {
        guard year >= 1986, weekday(year: year, month: month, day: day) != 1 else { return false }
        let o = ordinal(year: year, month: month, day: day)
        let (py, pm, pd) = civil(ordinal: o - 1)
        let (ny, nm, nd) = civil(ordinal: o + 1)
        return fixedOrRuleBased(year: py, month: pm, day: pd) && fixedOrRuleBased(year: ny, month: nm, day: nd)
    }

    // MARK: - 日付計算（グレゴリオ暦）

    static func vernalEquinoxDay(_ year: Int) -> Int {
        Int((20.8431 + 0.242194 * Double(year - 1980)).rounded(.down)) - (year - 1980) / 4
    }

    static func autumnalEquinoxDay(_ year: Int) -> Int {
        Int((23.2488 + 0.242194 * Double(year - 1980)).rounded(.down)) - (year - 1980) / 4
    }

    /// n 番目の月曜の日
    static func nthMonday(_ n: Int, year: Int, month: Int) -> Int {
        let w = weekday(year: year, month: month, day: 1) // 1=日 … 7=土
        let firstMonday = w <= 2 ? 3 - w : 10 - w
        return firstMonday + (n - 1) * 7
    }

    /// 曜日。1=日曜 … 7=土曜（Calendar.component(.weekday) と同じ）
    public static func weekday(year: Int, month: Int, day: Int) -> Int {
        // 1970-01-01 は木曜（5）
        let o = ordinal(year: year, month: month, day: day)
        return ((o + 4) % 7 + 7) % 7 + 1
    }

    /// 1970-01-01 を 0 とする通算日
    static func ordinal(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(ordinal z: Int) -> (Int, Int, Int) {
        let z = z + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
