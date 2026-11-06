import Foundation
import Core

/// 相談役に渡す「アプリの記録」の要約（F-53）。端末内の言語モデルの文脈に収まるよう 3,000 文字程度に抑える。
@MainActor
enum AssistantContext {
    static func build(services: AppServices, home: HomeViewModel, question: String = "", now: Date = .now) async -> String {
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

        // 釣り場ごとの予報（今日・明日・明後日の最高釣れ率と最良の時間帯、明日の天気）。質問に出た港も足す
        var targets: [(name: String, coordinate: Coordinate)] = spots.filter { $0.isRegistered && $0.coordinate.isPlausible }.prefix(5).map { ($0.name, $0.coordinate) }
        if let home = home.spot, !targets.contains(where: { $0.name == home.name }) { targets.insert((home.name, home.coordinate), at: 0) }
        for port in portsMentioned(in: question) where !targets.contains(where: { $0.name == port.name || Geo.distanceMeters($0.coordinate, port.coordinate) < 500 }) {
            targets.append((port.name, port.coordinate))
        }
        if !targets.isEmpty {
            lines.append("釣り場ごとの予報（釣れ率は 0〜100、アプリの計算。これを根拠に「釣れそうか」に答えてよい）:")
            for t in targets.prefix(6) {
                lines.append(await forecastLine(name: t.name, coordinate: t.coordinate, services: services, timeZone: tz, now: now, fmt: fmt))
            }
        }
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
        if text.count > 3800 { text = String(text.prefix(3800)) }
        return text
    }

    /// 質問に出てきた港（同梱の港データ。かな・漢字）。最大 2 件
    private static func portsMentioned(in question: String) -> [Core.Port] {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        PortReadingIndex.shared.prepare(catalog: PortCatalog.bundled())
        let names = PortReadingIndex.shared.entries
        // 港名（漁港・港を除いた部分）が質問に含まれるもの。長い名前を優先
        let hits = names.filter { e in
            let base = e.name.replacingOccurrences(of: "漁港", with: "").replacingOccurrences(of: "港", with: "")
            return base.count >= 2 && q.contains(base)
        }
        .sorted { $0.name.count > $1.name.count }
        return hits.prefix(2).map(\.port)
    }

    /// 1 つの釣り場の 3 日分：最高釣れ率と最良の時間帯、明日の天気（風・気温・降水・波）
    private static func forecastLine(name: String, coordinate: Coordinate, services: AppServices, timeZone tz: TimeZone, now: Date, fmt: (Date, String) -> String) async -> String {
        let env = services.environment
        await env.refreshIfNeeded(at: coordinate, now: now)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let start = cal.startOfDay(for: now)
        let tide = env.tideStation(near: coordinate).map { TideEngine(station: $0) }
        let calc = HomeViewModel.DayCalculator(engine: ScoreEngine(), builder: env.builder(for: coordinate), inputs: env.inputs(for: coordinate), tide: tide,
                                               coordinate: coordinate, timeZone: tz, horizon: env.forecastHorizon(for: coordinate))
        var parts: [String] = []
        for offset in 0..<3 {
            let dayStart = start.addingTimeInterval(Double(offset) * 86_400)
            let day = calc.compute(from: dayStart)
            let points = offset == 0 ? day.timeline.filter { $0.at >= now } : day.timeline
            guard let best = ScoreTimeline.bestWindow(points), let top = points.map(\.score).max() else { continue }
            let label = offset == 0 ? "今日" : (offset == 1 ? "明日" : "明後日")
            var text = "\(label)(\(fmt(dayStart, "M/d"))) 最高\(top) 最良\(fmt(best.start, "H:mm"))〜\(fmt(best.end, "H:mm"))"
            if offset == 1 {
                let e = env.snapshot(at: dayStart.addingTimeInterval(9 * 3600), coordinate: coordinate)
                var w: [String] = []
                if let v = e.windSpeedMS { w.append("風\(Int(v.rounded()))m/s" + (e.windDirectionDeg.map { HomeViewModel.compass($0) } ?? "")) }
                if let t = e.airTemperatureC { w.append("気温\(Int(t.rounded()))°") }
                if let p = e.precipitationChance { w.append("降水\(Int((p * 100).rounded()))%") }
                if let h = e.waveHeightM { w.append(String(format: "波%.1fm", h)) }
                if !w.isEmpty { text += "（9時 " + w.joined(separator: " ") + "）" }
            }
            parts.append(text)
        }
        return "- \(name): " + (parts.isEmpty ? "予報なし" : parts.joined(separator: " / "))
    }
}
