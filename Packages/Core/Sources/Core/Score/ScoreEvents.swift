import Foundation

/// 「次に変わる出来事」の列（ホームのイベント列）。マズメ・満干・風の変化を時刻順に。
public struct ScoreEvent: Hashable, Sendable {
    public enum Kind: String, Sendable { case dawn, dusk, highTide, lowTide, windUp, windDown, sunrise, sunset }
    public var at: Date
    public var kind: Kind
    public var label: String
    /// 釣れ率が上がる出来事ならオレンジ、下がるならグレー
    public var isPositive: Bool
    public init(at: Date, kind: Kind, label: String, isPositive: Bool) {
        self.at = at; self.kind = kind; self.label = label; self.isPositive = isPositive
    }
}

public enum ScoreEvents {
    /// `wind` は (時刻, m/s) の予報列。しきい値 5 m/s を跨ぐところを「風 3→6m/s」のように出す。
    public static func upcoming(from: Date, count: Int = 3, coordinate: Coordinate, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current,
                                tideExtremes: [TideExtreme], wind: [(Date, Double)] = [], windThresholdMS: Double = 5) -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        // マズメ：今日と明日
        for dayOffset in 0...1 {
            let day = from.addingTimeInterval(Double(dayOffset) * 86_400)
            let sun = SunCalculator.times(on: day, at: coordinate, timeZone: timeZone)
            if let dawn = sun.civilDawn { events.append(ScoreEvent(at: dawn, kind: .dawn, label: "朝マズメ", isPositive: true)) }
            if let dusk = sun.sunset { events.append(ScoreEvent(at: dusk.addingTimeInterval(-30 * 60), kind: .dusk, label: "夕マズメ", isPositive: true)) }
        }
        for e in tideExtremes {
            events.append(ScoreEvent(at: e.at, kind: e.kind == .high ? .highTide : .lowTide, label: e.kind == .high ? "満潮" : "干潮", isPositive: false))
        }
        let sorted = wind.sorted { $0.0 < $1.0 }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            if a.1 < windThresholdMS && b.1 >= windThresholdMS {
                events.append(ScoreEvent(at: b.0, kind: .windUp, label: "風 \(Int(a.1.rounded()))→\(Int(b.1.rounded()))m/s", isPositive: false))
            } else if a.1 >= windThresholdMS && b.1 < windThresholdMS {
                events.append(ScoreEvent(at: b.0, kind: .windDown, label: "風 \(Int(a.1.rounded()))→\(Int(b.1.rounded()))m/s", isPositive: true))
            }
        }
        return Array(events.filter { $0.at > from }.sorted { $0.at < $1.at }.prefix(count))
    }
}
