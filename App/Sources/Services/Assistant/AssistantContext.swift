import Foundation
import Core

/// 相談役に渡す「アプリの記録」の要約（F-53）。端末内の言語モデルの文脈に収まるよう 3,000 文字程度に抑える。
@MainActor
enum AssistantContext {
    static func build(services: AppServices, home: HomeViewModel, now: Date = .now) -> String {
        let store = services.store
        let tz = home.timeZone
        var lines: [String] = []
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.timeZone = tz
        func fmt(_ d: Date, _ format: String) -> String { f.dateFormat = format; return f.string(from: d) }
        lines.append("今日: \(fmt(now, "M月d日(E) H:mm"))")
        if let spot = home.spot { lines.append("ホームの釣り場: \(spot.name)") }
        if let s = home.score { lines.append("今の釣れ率: \(s.score)\(s.isForecast ? "（予報）" : "")") }
        for chip in home.chips { lines.append("\(chip.label): \(chip.value)") }
        if !home.weekOutlook.isEmpty {
            let week = home.weekOutlook.compactMap { d -> String? in
                guard let m = d.maxScore else { return nil }
                return "\(fmt(d.dayStart, "M/d(E)")) 最高\(m)"
            }
            lines.append("週の見通し: " + week.joined(separator: " / "))
        }
        if let next = home.tideExtremes.first {
            lines.append("次の潮: \(next.kind == .high ? "満潮" : "干潮") \(fmt(next.at, "H:mm")) \(Int(next.levelCm.rounded()))cm")
        }

        let sessions = (try? store.sessions()) ?? []
        let spots = (try? store.spots()) ?? []
        let spotName: (UUID) -> String = { id in spots.first { $0.id == id }?.name ?? "釣り場" }
        let closed = sessions.filter { !$0.isActive }
        lines.append("釣行: \(closed.count) 回、釣果 \(closed.flatMap(\.catches).count) 尾")
        for s in closed.prefix(6) {
            let species = Dictionary(grouping: s.catches, by: \.species).map { "\($0.key.isEmpty ? "魚" : $0.key)\($0.value.count)" }.joined(separator: " ")
            let minutes = Int((s.duration ?? 0) / 60)
            lines.append("- \(fmt(s.startedAt, "M/d H:mm")) \(spotName(s.spotID)) \(minutes)分 \(s.catches.isEmpty ? "ボウズ" : species)")
        }
        let speciesStats = Analytics.speciesStats(catches: closed.flatMap(\.catches), timeZone: tz).prefix(8)
        if !speciesStats.isEmpty {
            lines.append("魚種別: " + speciesStats.map { "\($0.species)\($0.count)尾" + ($0.maxLengthCm.map { String(format: " 最大%.0fcm", $0) } ?? "") }.joined(separator: "、"))
        }
        let registered = spots.filter(\.isRegistered)
        if !registered.isEmpty {
            lines.append("登録した釣り場: " + registered.prefix(12).map { sp in
                let ss = closed.filter { $0.spotID == sp.id }
                return "\(sp.name)（\(ss.count)釣行 \(ss.flatMap(\.catches).count)尾）"
            }.joined(separator: "、"))
        }
        let notes = (try? store.notes()) ?? []
        if !notes.isEmpty {
            lines.append("地図のメモ:")
            for n in notes.prefix(12) {
                lines.append("- \(fmt(n.createdAt, "M/d")) \(n.placeName ?? "") \(n.text)")
            }
        }
        let feeds = services.feeds.items.prefix(5)
        if !feeds.isEmpty {
            lines.append("釣果情報（ネット）:")
            for f in feeds { lines.append("- \(f.title)") }
        }
        var text = lines.joined(separator: "\n")
        if text.count > 3200 { text = String(text.prefix(3200)) }
        return text
    }
}
