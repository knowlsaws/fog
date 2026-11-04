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
    /// グラフに出している日（0 = 今日、-1 = 昨日、+n = n 日後）
    var dayOffset: Int = 0 { didSet { updateDay(); updateWeekOutlook() } }
    private(set) var dayStart: Date = .now
    private(set) var dayEnd: Date = .now
    private(set) var dayTimeline: [ScorePoint] = []
    private(set) var dayTide: [TidePoint] = []
    private(set) var dayExtremes: [TideExtreme] = []
    /// その日の 0,3,…,21 時の環境（詳細表）
    private(set) var dayDetail: [EnvSnapshot] = []
    private(set) var seaSurfaceTempC: Double?
    private(set) var nextFetchAt: Date?
    /// 今の潮位（cm）と変化率（cm/時、正で上げ）
    private(set) var nowTideLevelCm: Double?
    private(set) var nowTideRateCmPerHour: Double?
    /// 表示中の日の日の出入・月の出入
    private(set) var daySun: SunTimes?
    private(set) var dayMoon: MoonTimes?
    /// 週間の見通し（今日から 7 日）：その日の最高釣れ率と昼の天気
    struct DayOutlook: Identifiable {
        let offset: Int
        let dayStart: Date
        let maxScore: Int
        let conditionCode: String?
        var id: Int { offset }
    }
    private(set) var weekOutlook: [DayOutlook] = []

    private var services: AppServices?
    private let cache = AnalysisCache()
    private var timelineKey = ""
    private var dayCache: [Int: DayData] = [:]
    private var calc: DayCalculator?
    /// 右軸の目盛りに使う潮位の範囲（1 か月）
    private(set) var tideRangeCm: ClosedRange<Double> = 0...200

    struct DayData { let timeline: [ScorePoint]; let tide: [TidePoint]; let extremes: [TideExtreme] }

    /// 1 日分の推移・潮位曲線・満干を計算する（純粋な計算。約 50 ms）
    struct DayCalculator {
        let engine: ScoreEngine
        let builder: EnvSnapshotBuilder
        let inputs: EnvSnapshotBuilder.Inputs
        let tide: TideEngine?
        let coordinate: Coordinate
        let timeZone: TimeZone
        let horizon: Date?

        func compute(from start: Date) -> DayData {
            let end = start.addingTimeInterval(86_400)
            let extremes = tide?.extremes(from: start.addingTimeInterval(-6 * 3600), to: end.addingTimeInterval(6 * 3600)) ?? []
            let timeline = ScoreTimeline.compute(engine: engine, coordinate: coordinate, from: start, to: end, stepMinutes: 15, timeZone: timeZone) { t in
                var e = builder.build(at: t, coordinate: coordinate, inputs: inputs, tide: tide, extremes: extremes)
                if let h = horizon, t > h { e.isForecast = true }
                return e
            }
            let curve = stride(from: 0, through: 86_400, by: 600).compactMap { offset -> TidePoint? in
                let t = start.addingTimeInterval(offset)
                return tide.map { TidePoint(at: t, levelCm: $0.level(at: t)) }
            }
            return DayData(timeline: timeline, tide: curve, extremes: extremes.filter { $0.at >= start && $0.at <= end })
        }
    }

    /// オフセット日のデータ（キャッシュ）
    private func dayData(_ offset: Int) -> DayData {
        if let d = dayCache[offset] { return d }
        guard let calc else { return DayData(timeline: [], tide: [], extremes: []) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let start = cal.startOfDay(for: now).addingTimeInterval(Double(offset) * 86_400)
        let d = calc.compute(from: start)
        dayCache[offset] = d
        return d
    }
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
        // 位置の無い釣行（室内の試し撮りなど）は、ホームの釣り場選びと「記録中」の対象にしない
        let allSpots = (try? store.spots()) ?? []
        let active = sessions.first { s in s.isActive && (allSpots.first { $0.id == s.spotID }?.coordinate.isPlausible ?? false) }
        isRecording = active != nil

        // 釣り場：記録中の釣行 → 選択中 → 現在地に最も近い登録釣り場 → 直近の釣行の釣り場
        // 位置が無い（0, 0）釣り場はホームの対象にしない
        let spots = ((try? store.spots()) ?? []).filter { $0.coordinate.isPlausible }
        let selectedRaw = UserDefaults.standard.string(forKey: "fog.homeSpotID")
        let useCurrentLocation = selectedRaw == Self.currentLocationKey
        let selectedID = selectedRaw.flatMap(UUID.init(uuidString:))
        let location = services.location.lastFix?.coordinate
        if let active, let s = spots.first(where: { $0.id == active.spotID }) {
            spot = s
        } else if active != nil || useCurrentLocation {
            spot = nil
        } else if let selectedID, let s = spots.first(where: { $0.id == selectedID }) {
            spot = s
        } else if let location, let nearest = spots.filter(\.isRegistered).min(by: { Geo.distanceMeters($0.coordinate, location) < Geo.distanceMeters($1.coordinate, location) }) {
            spot = nearest
        } else if let last = sessions.first, let s = spots.first(where: { $0.id == last.spotID }) {
            spot = s
        }
        let candidate = active?.track.last?.coordinate ?? spot?.coordinate ?? location ?? SampleData.hakodate
        coordinate = candidate.isPlausible ? candidate : (location ?? SampleData.hakodate)

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

        chips = makeChips(current, fetchFailed: env.lastError != nil)

        // 推移：前日の 0 時から 31 日先まで（潮・天文は無期限、天気は約 10 日先まで。その先は線を薄く）。
        // 1 日分ずつ必要になったときに計算してキャッシュする（31 日分を一度に計算すると 1.5 秒かかる）。
        // 場所・予報・保存データ・日付が変わったらキャッシュを捨てる
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let start = cal.startOfDay(for: now).addingTimeInterval(-86_400)
        forecastHorizon = env.forecastHorizon(for: coordinate)
        let end = start.addingTimeInterval(32 * 86_400)
        let entry = env.cache.entry(for: coordinate)
        let key = [String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude), "\(entry?.weatherFetchedAt?.timeIntervalSince1970 ?? 0)",
                   "\(entry?.marineFetchedAt?.timeIntervalSince1970 ?? 0)", "\(store.revision)", "\(start.timeIntervalSince1970)"].joined(separator: "|")
        let station = env.tideStation(near: coordinate)
        let tide = station.map { TideEngine(station: $0) }
        let inputs = env.inputs(for: coordinate)
        if key != timelineKey {
            timelineKey = key
            rangeStart = start; rangeEnd = end
            dayCache = [:]
            calc = DayCalculator(engine: engine, builder: env.builder(for: coordinate), inputs: inputs, tide: tide, coordinate: coordinate, timeZone: timeZone, horizon: forecastHorizon)
            // 右軸の目盛り用：1 か月の潮位の範囲（1 時間おき）
            if let tide {
                let levels = stride(from: 0, to: end.timeIntervalSince(start), by: 3600).map { tide.level(at: start.addingTimeInterval($0)) }
                if let lo = levels.min(), let hi = levels.max(), hi > lo { tideRangeCm = lo...hi }
            }
        }
        updateDay()
        updateWeekOutlook()
        let todayData = dayData(0)
        tideExtremes = tide?.extremes(from: now, to: now.addingTimeInterval(3 * 86_400)) ?? []
        timeline = todayData.timeline + dayData(1).timeline + dayData(2).timeline
        sunTimesByDay = daySun.map { [$0] } ?? []
        seaSurfaceTempC = current.seaSurfaceTempC
        nowTideLevelCm = current.tideLevelCm
        nowTideRateCmPerHour = current.tideRateCmPerHour
        nextFetchAt = env.gate.nextAllowed("weather:" + ForecastCache.key(for: coordinate))
        let wind = inputs.weather.compactMap { s in s.windSpeedMS.map { (s.at, $0) } }
        events = ScoreEvents.upcoming(from: now, count: 3, coordinate: coordinate, timeZone: timeZone, tideExtremes: tideExtremes, wind: wind)

        // ウィジェット（15 分更新）とピーク通知（§8）
        let widgetEvents = ScoreEvents.upcoming(from: now, count: 16, coordinate: coordinate, timeZone: timeZone, tideExtremes: tideExtremes, wind: wind)
        WidgetSync.publish(spotName: spot?.name ?? "", timeline: timeline, tide: tide, events: widgetEvents, isRecording: isRecording, tackle: services.capture.currentTackle)
        PeakNotifier.schedule(points: timeline, spot: spot, now: now, timeZone: timeZone)
    }

    /// チップ詳細の「再取得」：1 時間の間隔制限を無視して気象・海況を取りに行く。
    func forceRefreshEnvironment() async {
        guard let services else { return }
        await services.environment.refreshIfNeeded(at: coordinate, now: .now, force: true)
        await refresh()
    }

    /// 日単位の範囲。前日から推移の終わりまでの間に収める
    var dayOffsetRange: ClosedRange<Int> {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        let first = Int((rangeStart.timeIntervalSince(today) / 86_400).rounded(.down))
        let last = Int((rangeEnd.timeIntervalSince(today) / 86_400).rounded(.down)) - 1
        return min(first, 0)...max(last, 0)
    }

    private func updateDay() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        let offset = min(max(dayOffset, dayOffsetRange.lowerBound), dayOffsetRange.upperBound)
        dayStart = today.addingTimeInterval(Double(offset) * 86_400)
        dayEnd = dayStart.addingTimeInterval(86_400)
        let data = dayData(offset)
        dayTimeline = data.timeline
        dayTide = data.tide
        dayExtremes = data.extremes
        if let services {
            dayDetail = stride(from: 0, to: 24, by: 3).map { h in services.environment.snapshot(at: dayStart.addingTimeInterval(Double(h) * 3600), coordinate: coordinate) }
        }
        let noon = dayStart.addingTimeInterval(12 * 3600)
        daySun = SunCalculator.times(on: noon, at: coordinate, timeZone: timeZone)
        dayMoon = MoonCalculator.times(on: noon, at: coordinate, timeZone: timeZone)
    }

    /// 週間の見通し：表示中の日の前日から 7 日分（表示中の日に合わせて動く）。各日の最高釣れ率と昼 12 時の天気
    private func updateWeekOutlook() {
        let range = dayOffsetRange
        var first = max(range.lowerBound, dayOffset - 1)
        if first + 6 > range.upperBound { first = max(range.lowerBound, range.upperBound - 6) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        var out: [DayOutlook] = []
        for offset in first...min(range.upperBound, first + 6) {
            let start = today.addingTimeInterval(Double(offset) * 86_400)
            guard let best = dayData(offset).timeline.map(\.score).max() else { continue }
            let noon = start.addingTimeInterval(12 * 3600)
            let cond = services.map { $0.environment.snapshot(at: noon, coordinate: coordinate).conditionCode } ?? nil
            let beyond = forecastHorizon.map { noon > $0 } ?? true
            out.append(DayOutlook(offset: offset, dayStart: start, maxScore: best, conditionCode: beyond ? nil : cond))
        }
        weekOutlook = out
    }

    /// イベント列のタップ：その時刻の日へ
    func show(date: Date) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        dayOffset = Int((cal.startOfDay(for: date).timeIntervalSince(today) / 86_400).rounded())
    }

    static let currentLocationKey = "current"

    func select(spot: Spot) {
        UserDefaults.standard.set(spot.id.uuidString, forKey: "fog.homeSpotID")
        Task { await refresh() }
    }

    /// 「現在地」を選ぶ：登録釣り場があっても今いる場所の情報を出す
    func selectCurrentLocation() {
        UserDefaults.standard.set(Self.currentLocationKey, forKey: "fog.homeSpotID")
        Task { await refresh() }
    }

    /// 同梱の港データから漁港を選んで釣り場に登録し、ホームの釣り場にする
    func select(port: Core.Port) {
        guard let services else { return }
        let existing = (try? services.store.spots()) ?? []
        if let same = existing.first(where: { Geo.distanceMeters($0.coordinate, port.coordinate) < 300 }) {
            var s = same; s.isRegistered = true
            try? services.store.upsert(s)
            select(spot: s)
            return
        }
        let spot = Spot(name: port.name, coordinate: port.coordinate, isRegistered: true)
        try? services.store.upsert(spot)
        select(spot: spot)
    }

    var availableSpots: [Spot] { ((try? services?.store.spots()) ?? []).filter { $0.isRegistered && $0.coordinate.isPlausible } }

    var isUsingCurrentLocation: Bool { UserDefaults.standard.string(forKey: "fog.homeSpotID") == Self.currentLocationKey }

    var currentLocation: Coordinate? { services?.location.lastFix?.coordinate }

    private static let portCatalog = PortCatalog.bundled()

    /// 近い順の漁港（検索語があれば全国から名前で絞る）
    func ports(matching query: String, limit: Int = 30) -> [Core.Port] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let base = Self.portCatalog.ports
        let origin = currentLocation ?? coordinate
        let filtered = q.isEmpty ? base : base.filter { $0.name.contains(q) }
        return filtered.sorted { Geo.distanceMeters($0.coordinate, origin) < Geo.distanceMeters($1.coordinate, origin) }.prefix(limit).map { $0 }
    }

    /// 4 チップ：値は「次の出来事の時刻」か「今の数値」。残り時間は出さない（時刻と紛らわしいため）。
    private func makeChips(_ env: EnvSnapshot, fetchFailed: Bool) -> [Chip] {
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
            out.append(Chip(kind: .wind, symbol: "wind", value: "—", label: fetchFailed ? "風 取得できず" : "風 取得中", tone: .normal))
        }
        // 天気：気温と天気の名前
        let temp = env.airTemperatureC.map { "\(Int($0.rounded()))°" } ?? "—"
        out.append(Chip(kind: .weather, symbol: Self.weatherSymbol(env.conditionCode), value: temp,
                        label: env.airTemperatureC == nil ? (fetchFailed ? "天気 取得できず" : "天気 取得中") : Self.weatherName(env.conditionCode, precipitation: env.precipitationMM),
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
