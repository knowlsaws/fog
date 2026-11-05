import Foundation

/// 釣行中の安全通知（F-36）：日の入り 30 分前、登録した帰る時間、次の満潮 1 時間前。
public enum SafetyPlanner {
    public enum Kind: String, Hashable, Sendable, CaseIterable { case sunset, homeTime, highTide }

    public struct Alert: Hashable, Sendable {
        public var kind: Kind
        public var fireAt: Date
        public var title: String
        public var body: String
    }

    /// `homeTime` は「今日の何時何分」（分単位、0〜1439）。`nextHighTide` は次の満潮。
    /// `now` より後に鳴るものだけ返す。
    public static func plan(now: Date, sunset: Date?, nextHighTide: Date?, homeTimeMinutes: Int?,
                            timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> [Alert] {
        var out: [Alert] = []
        let f = DateFormatter(); f.timeZone = timeZone; f.dateFormat = "H:mm"
        if let sunset {
            let at = sunset.addingTimeInterval(-30 * 60)
            if at > now { out.append(Alert(kind: .sunset, fireAt: at, title: "日の入りまで 30 分", body: "\(f.string(from: sunset)) に暗くなります。足元と帰り道を確認")) }
        }
        if let minutes = homeTimeMinutes, (0..<1440).contains(minutes) {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
            if let at = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now), at > now {
                out.append(Alert(kind: .homeTime, fireAt: at, title: "帰る時間", body: "\(f.string(from: at)) に設定した時間です"))
            }
        }
        if let high = nextHighTide {
            let at = high.addingTimeInterval(-3600)
            if at > now { out.append(Alert(kind: .highTide, fireAt: at, title: "満潮まで 1 時間", body: "\(f.string(from: high)) に満潮。低い場所は早めに退避")) }
        }
        return out.sorted { $0.fireAt < $1.fireAt }
    }
}
