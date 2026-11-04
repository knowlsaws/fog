import Foundation

/// 気象庁 潮位表テキスト版（https://www.data.jma.go.jp/kaiyou/db/tide/suisan/readme.html）のパーサ。
/// 1行 = 毎時潮位 24 個（各3桁、1〜72桁）＋年月日（73〜78桁、YYMMDD）＋地点記号（79〜80桁）
/// ＋満潮4組（時刻4桁＋潮位3桁 = 7桁 × 4、81〜108桁）＋干潮4組（109〜136桁）。予測なしは時刻 9999・潮位 999。
public struct JMATideTableDay: Hashable, Sendable {
    public var date: DateComponents            // year, month, day（JST）
    public var stationCode: String
    public var hourlyLevelsCm: [Double?]       // 0〜23 時
    public var highTides: [(time: DateComponents, levelCm: Double)]
    public var lowTides: [(time: DateComponents, levelCm: Double)]

    public static func == (lhs: JMATideTableDay, rhs: JMATideTableDay) -> Bool {
        lhs.date == rhs.date && lhs.stationCode == rhs.stationCode && lhs.hourlyLevelsCm == rhs.hourlyLevelsCm
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(date); hasher.combine(stationCode) }

    /// その日の 0 時（JST）
    public func dayStart(timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo")!) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: date)
    }

    /// 毎時の (Date, 潮位) の組
    public func hourlySamples(timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo")!) -> [(Date, Double)] {
        guard let start = dayStart(timeZone: timeZone) else { return [] }
        return hourlyLevelsCm.enumerated().compactMap { i, v in
            v.map { (start.addingTimeInterval(Double(i) * 3600), $0) }
        }
    }

    /// 満干の (Date, 潮位, 満潮か)
    public func extremes(timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo")!) -> [(Date, Double, Bool)] {
        guard let start = dayStart(timeZone: timeZone) else { return [] }
        func toDate(_ c: DateComponents) -> Date {
            start.addingTimeInterval(Double(c.hour ?? 0) * 3600 + Double(c.minute ?? 0) * 60)
        }
        return highTides.map { (toDate($0.time), $0.levelCm, true) } + lowTides.map { (toDate($0.time), $0.levelCm, false) }
    }
}

public enum JMATideTableParser {
    public static func parse(_ text: String) -> [JMATideTableDay] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ raw: String) -> JMATideTableDay? {
        let line = raw.replacingOccurrences(of: "\r", with: "")
        guard line.count >= 80 else { return nil }
        let chars = Array(line)
        func field(_ start: Int, _ length: Int) -> String {
            let end = min(chars.count, start - 1 + length)
            guard start - 1 < chars.count else { return "" }
            return String(chars[(start - 1)..<end])
        }
        var hourly: [Double?] = []
        for i in 0..<24 {
            let s = field(1 + i * 3, 3).trimmingCharacters(in: .whitespaces)
            hourly.append(s == "999" ? nil : Double(s))
        }
        let yy = Int(field(73, 2).trimmingCharacters(in: .whitespaces)) ?? 0
        let mm = Int(field(75, 2).trimmingCharacters(in: .whitespaces)) ?? 0
        let dd = Int(field(77, 2).trimmingCharacters(in: .whitespaces)) ?? 0
        guard mm >= 1, mm <= 12, dd >= 1, dd <= 31 else { return nil }
        let year = yy + 2000
        let code = field(79, 2)
        func tides(_ start: Int) -> [(DateComponents, Double)] {
            var out: [(DateComponents, Double)] = []
            for k in 0..<4 {
                let t = field(start + k * 7, 4).trimmingCharacters(in: .whitespaces)
                let l = field(start + k * 7 + 4, 3).trimmingCharacters(in: .whitespaces)
                guard t != "9999", t.count == 4, let hh = Int(t.prefix(2)), let mi = Int(t.suffix(2)), let level = Double(l) else { continue }
                out.append((DateComponents(hour: hh, minute: mi), level))
            }
            return out
        }
        return JMATideTableDay(
            date: DateComponents(year: year, month: mm, day: dd),
            stationCode: code,
            hourlyLevelsCm: hourly,
            highTides: tides(81),
            lowTides: tides(109)
        )
    }
}
