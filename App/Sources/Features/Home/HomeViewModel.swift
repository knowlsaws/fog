import Foundation
import SwiftUI
import Core

/// ホーム画面の状態（§3）。今の釣れ率・内訳・魚種別、4 チップ、イベント列、先の推移と潮位曲線を保存データと端末計算から作る。
@MainActor
@Observable
final class HomeViewModel {
    struct Chip: Identifiable {
        enum Kind: String { case tide, light, wind, weather }
        enum Tone { case good, normal, bad }
        let kind: Kind
        var symbol: String
        /// 大きく出す値（時刻・風速・気温）
        var value: String
        /// 値の意味（満潮・朝マズメ・北西・晴れ）
        var label: String
        var tone: Tone
        var id: String { kind.rawValue }
        var text: String { label.isEmpty ? value : "\(label) \(value)" }
    }

    struct TidePoint: Identifiable {
        let at: Date
        let levelCm: Double
        var id: Date { at }
    }

    private(set) var spot: Spot?
    private(set) var coordinate: Coordinate = SampleData.hakodate
    private(set) var now: Date = .now
    private(set) var score: ScoreResult?
    private(set) var speciesScores: [(species: String, score: Int)] = []
    private(set) var chips: [Chip] = []
    private(set) var events: [ScoreEvent] = []
    private(set) var timeline: [ScorePoint] = []
    private(set) var tideCurve: [TidePoint] = []
    private(set) var tideExtremes: [TideExtreme] = []
    private(set) var sunTimesByDay: [SunTimes] = []
    private(set) var forecastHorizon: Date?
    private(set) var isRecording = false
    private(set) var moonAge: Double = 0
    private(set) var rangeStart: Date = .now
    private(set) var rangeEnd: Date = .now
    var scrollTarget: Date?

    private var services: AppServices?
    private let cache = AnalysisCache()
    let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

    func attach(_ services: AppServices) {
        self.services = services
    }

    /// 全部を計算し直す（起動時・30 秒ごと・釣り場切替・ストア変更時）。
    func refresh(now: Date = .now) async {
        guard let services else { return }
        self.now = now
        let store = services.store
        let env = services.environment
        let sessions = (try? store.sessions()) ?? []
        let active = sessions.first { $0.isActive }
        isRecording = active != nil

        // 釣り場：記録中の釣行 → 選択中 → 現在地に最も近い登録釣り場 → 直近の釣行の釣り場
        let spots = (try? store.spots()) ?? []
        let selectedID = UserDefaults.standard.string(forKey: "fog.homeSpotID").flatMap(UUID.init(uuidString:))
        let location = services.location.lastFix?.coordinate
        if let active, let s = spots.first(where: { $0.id == active.spotID }) {
            spot = s
        } else if let selectedID, let s = spots.first(where: { $0.id == selectedID }) {
            spot = s
        } else if let location, let nearest = spots.filter(\.isRegistered).min(by: { Geo.distanceMeters($0.coordinate, location) < Geo.distanceMeters($1.coordinate, location) }) {
            spot = nearest
        } else if let last = sessions.first, let s = spots.first(where: { $0.id == last.spotID }) {
            spot = s
        }
        coordinate = active?.track.last?.coordinate ?? spot?.coordinate ?? location ?? SampleData.hakodate

        // 自分データの重み（削除が即時反映されるよう revision で捨てる）
        let personal = cache.value("personalModel", store: store) {
            PersonalModel.learn(from: sessions.filter { !$0.isActive }, coordinateOf: { s in spots.first { $0.id == s.spotID }?.coordinate }, timeZone: timeZone)
        }
        let engine = ScoreEngine(personal: personal.total.hours >= 1 ? personal : nil)
        await env.refreshIfNeeded(at: coordinate, now: now)
        let current = env.snapshot(at: now, coordinate: coordinate)
        score = engine.score(ScoreInput(at: now, coordinate: coordinate, env: current, timeZone: timeZone))
        moonAge = current.moonAge ?? MoonCalculator.age(at: now)

        // 魚種別（自分が釣った魚種の上位 3）
        let topSpecies = Analytics.speciesStats(sessions: sessions, timeZone: timeZone).prefix(3).map(\.species)
        speciesScores = topSpecies.map { name in
            (species: name, score: engine.score(ScoreInput(at: now, coordinate: coordinate, env: current, species: name, timeZone: timeZone)).score)
        }

        chips = makeChips(current)

        // 推移：今日の 0 時から予報のある範囲（最低 48 時間）まで 15 分刻み。潮は無期限なので潮位曲線は同じ範囲
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let start = cal.startOfDay(for: now)
        forecastHorizon = env.forecastHorizon(for: coordinate)
        let end = max(forecastHorizon ?? start, start.addingTimeInterval(48 * 3600))
        rangeStart = start; rangeEnd = end
        let station = env.tideStation(near: coordinate)
        let tide = station.map { TideEngine(station: $0) }
        tideExtremes = tide?.extremes(from: start, to: end) ?? []
        let inputs = env.inputs(for: coordinate)
        let builder = env.builder(for: coordinate)
        timeline = ScoreTimeline.compute(engine: engine, coordinate: coordinate, from: start, to: end, stepMinutes: 15, timeZone: timeZone) { t in
            var e = builder.build(at: t, coordinate: coordinate, inputs: inputs, tide: tide, extremes: tideExtremes)
            if let h = forecastHorizon, t > h { e.isForecast = true }
            return e
        }
        tideCurve = stride(from: 0, through: end.timeIntervalSince(start), by: 600).compactMap { offset in
            let t = start.addingTimeInterval(offset)
            return tide.map { TidePoint(at: t, levelCm: $0.level(at: t)) }
        }
        sunTimesByDay = stride(from: 0, through: end.timeIntervalSince(start), by: 86_400).map { SunCalculator.times(on: start.addingTimeInterval($0), at: coordinate, timeZone: timeZone) }
        let wind = inputs.weather.compactMap { s in s.windSpeedMS.map { (s.at, $0) } }
        events = ScoreEvents.upcoming(from: now, count: 3, coordinate: coordinate, timeZone: timeZone, tideExtremes: tideExtremes, wind: wind)

        // ウィジェット（15 分更新）とピーク通知（§8）
        let widgetEvents = ScoreEvents.upcoming(from: now, count: 16, coordinate: coordinate, timeZone: timeZone, tideExtremes: tideExtremes, wind: wind)
        WidgetSync.publish(spotName: spot?.name ?? "", timeline: timeline, tide: tide, events: widgetEvents, isRecording: isRecording, tackle: services.capture.currentTackle)
        PeakNotifier.schedule(points: timeline, spot: spot, now: now, timeZone: timeZone)
    }

    func select(spot: Spot) {
        UserDefaults.standard.set(spot.id.uuidString, forKey: "fog.homeSpotID")
        Task { await refresh() }
    }

    var availableSpots: [Spot] { ((try? services?.store.spots()) ?? []).filter(\.isRegistered) }

    /// 4 チップ：値は「次の出来事の時刻」か「今の数値」。残り時間は出さない（時刻と紛らわしいため）。
    private func makeChips(_ env: EnvSnapshot) -> [Chip] {
        var out: [Chip] = []
        // 潮：矢印（上げ／下げ／止まり）、次の満干の時刻、潮名
        let rate = env.tideRateCmPerHour ?? 0
        let next = [env.nextHighTideAt.map { ("満潮", $0) }, env.nextLowTideAt.map { ("干潮", $0) }].compactMap { $0 }.min { $0.1 < $1.1 }
        let tideLabel = [next?.0, env.tideName].compactMap { $0 }.joined(separator: " · ")
        out.append(Chip(kind: .tide, symbol: abs(rate) < 2 ? "minus" : (rate > 0 ? "arrow.up" : "arrow.down"),
                        value: next.map { Self.clock($0.1) } ?? "—", label: tideLabel.isEmpty ? "潮" : tideLabel,
                        tone: abs(rate) < 2 ? .bad : (abs(rate) >= 6 ? .good : .normal)))
        // 光：マズメ中はその名前、そうでなければ次のマズメの時刻
        let sun = SunCalculator.times(on: now, at: coordinate, timeZone: timeZone)
        let tomorrow = SunCalculator.times(on: now.addingTimeInterval(86_400), at: coordinate, timeZone: timeZone)
        let candidates: [(String, Date)] = [sun.civilDawn.map { ("朝マズメ", $0) }, sun.sunset.map { ("夕マズメ", $0.addingTimeInterval(-30 * 60)) }, tomorrow.civilDawn.map { ("朝マズメ", $0) }]
            .compactMap { $0 }.filter { $0.1 > now }
        let nextTwilight = candidates.min { $0.1 < $1.1 }
        let inMorning: Bool = { guard let dawn = sun.civilDawn, let sunrise = sun.sunrise else { return false }; return now >= dawn && now <= sunrise.addingTimeInterval(30 * 60) }()
        let inEvening: Bool = { guard let sunset = sun.sunset, let dusk = sun.civilDusk else { return false }; return now >= sunset.addingTimeInterval(-30 * 60) && now <= dusk }()
        if inMorning || inEvening {
            out.append(Chip(kind: .light, symbol: "sun.horizon.fill", value: inMorning ? "朝マズメ" : "夕マズメ", label: "いま", tone: .good))
        } else {
            let minutesTo = nextTwilight.map { $0.1.timeIntervalSince(now) / 60 } ?? 999
            out.append(Chip(kind: .light, symbol: minutesTo < 90 ? "sun.horizon" : "sun.max", value: nextTwilight.map { Self.clock($0.1) } ?? "—",
                            label: nextTwilight?.0 ?? "マズメ", tone: minutesTo < 90 ? .good : .normal))
        }
        // 風：風速と風向（吹いてくる方角）
        if let w = env.windSpeedMS {
            out.append(Chip(kind: .wind, symbol: "location.north.fill", value: "\(Int(w.rounded())) m/s",
                            label: env.windDirectionDeg.map { Self.compass($0) + "の風" } ?? "風", tone: w > 8 ? .bad : (w <= 3 ? .good : .normal)))
        } else {
            out.append(Chip(kind: .wind, symbol: "wind", value: "—", label: "風 取得中", tone: .normal))
        }
        // 天気：気温と天気の名前
        let temp = env.airTemperatureC.map { "\(Int($0.rounded()))°" } ?? "—"
        out.append(Chip(kind: .weather, symbol: Self.weatherSymbol(env.conditionCode), value: temp,
                        label: env.airTemperatureC == nil ? "天気 取得中" : Self.weatherName(env.conditionCode, precipitation: env.precipitationMM),
                        tone: (env.precipitationMM ?? 0) > 1 ? .bad : .normal))
        return out
    }

    static func clock(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }

    /// 風向（度、吹いてくる方角）→ 8 方位
    static func compass(_ deg: Double) -> String {
        let names = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        let i = Int(((deg + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8
        return names[max(0, i)]
    }

    static func weatherName(_ code: String?, precipitation: Double?) -> String {
        switch code ?? "" {
        case "clear", "mostlyClear": return "晴れ"
        case "partlyCloudy": return "晴れ時々曇り"
        case "cloudy", "mostlyCloudy": return "曇り"
        case "rain", "drizzle", "heavyRain": return "雨"
        case "snow", "flurries", "heavySnow": return "雪"
        case "foggy", "haze": return "霧"
        case "windy", "breezy": return "強風"
        default: return (precipitation ?? 0) > 0.5 ? "雨" : "曇り"
        }
    }

    static func weatherSymbol(_ code: String?) -> String {
        switch code ?? "" {
        case "clear", "mostlyClear": return "sun.max.fill"
        case "partlyCloudy": return "cloud.sun.fill"
        case "cloudy", "mostlyCloudy": return "cloud.fill"
        case "rain", "drizzle", "heavyRain": return "cloud.rain.fill"
        case "snow", "flurries", "heavySnow": return "cloud.snow.fill"
        case "foggy", "haze": return "cloud.fog.fill"
        case "windy", "breezy": return "wind"
        default: return "cloud.fill"
        }
    }

    static func hm(_ interval: TimeInterval) -> String {
        let m = max(0, Int(interval / 60))
        return "\(m / 60):\(String(format: "%02d", m % 60))"
    }

    var windDirectionDeg: Double? { services?.environment.snapshot(at: now, coordinate: coordinate).windDirectionDeg }
}
