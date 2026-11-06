import SwiftUI
import MapKit
import Core

/// 釣り場詳細：拡大地図にヒートマップ（オレンジ）と根掛かり（グレー）、良い条件の分布バー、魚種と尾数、よく使ったリグ。右上で名前の変更と削除。
struct SpotDetailView: View {
    let card: SpotsViewModel.Card
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [Core.Session] = []
    @State private var points: [Point] = []
    @State private var rigs: [UUID: Rig] = [:]
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: DS.Spacing.m) {
                ZStack(alignment: .topTrailing) {
                    heatmap.frame(height: geo.size.height * 0.38)
                    Menu {
                        Button("名前を変える") { newName = card.spot.name; renaming = true }
                        Button("削除", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill").font(.system(size: 22)).foregroundStyle(DS.Color.textPrimary).padding(DS.Spacing.l)
                    }
                }
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.spot.name).font(DS.Font.number(22)).foregroundStyle(DS.Color.textPrimary)
                        Spacer()
                        Text("\(card.stats.sessions)釣行 \(card.stats.catches)尾").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                    let dist = Analytics.conditionDistribution(of: sessions.flatMap(\.catches))
                    HStack(spacing: DS.Spacing.m) {
                        bars("時間帯", dist.byLight)
                        bars("潮", dist.byTide)
                        bars("風", dist.byWind)
                    }
                    HStack(spacing: DS.Spacing.m) {
                        ForEach(card.stats.topSpecies.prefix(4), id: \.species) { s in
                            HStack(spacing: 4) {
                                Text(s.species).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                                Text("\(s.count)").font(DS.Font.number(13)).foregroundStyle(DS.Color.textPrimary)
                            }
                        }
                        Spacer()
                    }
                    let rigStats = Analytics.rigStats(sessions: sessions).prefix(3)
                    if !rigStats.isEmpty {
                        HStack(spacing: DS.Spacing.m) {
                            ForEach(Array(rigStats), id: \.rigID) { r in
                                Text("\(r.rigID.flatMap { rigs[$0]?.displayName } ?? "リグ未設定") \(r.catches)尾")
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    briefing
                }
                .padding(.horizontal, DS.Spacing.l)
                Spacer(minLength: 0)
            }
        }
        .background(ThemeBackground(name: .bgDetail))
        .onAppear(perform: reload)
        .alert("名前", isPresented: $renaming) {
            TextField("釣り場名", text: $newName)
            Button("保存") { if !newName.isEmpty { var s = card.spot; s.name = newName; try? services.store.upsert(s) } }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("この釣り場と釣行を削除", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { try? services.store.deleteSpot(id: card.spot.id); dismiss() }
            Button("キャンセル", role: .cancel) {}
        }
    }

    /// 遠征の下調べ（F-37）：これから 30 日の潮回り（大潮ほど濃い）と、この釣り場で今の季節に釣れた魚
    private var briefing: some View {
        let tz = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c }()
        let days = TideCalendar.days(from: Date(), days: 30, timeZone: tz)
        let thisMonth = cal.component(.month, from: Date())
        let months = [thisMonth, thisMonth % 12 + 1]
        let catches = sessions.flatMap(\.catches)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("下調べ · 30 日の潮回り").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            HStack(spacing: 2) {
                ForEach(days, id: \.dayStart) { d in
                    let c = cal.dateComponents([.year, .month, .day, .weekday], from: d.dayStart)
                    let holiday = c.weekday == 1 || JapaneseHolidays.isHoliday(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
                    VStack(spacing: 1) {
                        Text("\(c.day ?? 0)").font(.system(size: 7, weight: .semibold, design: .rounded))
                            .foregroundStyle(holiday ? DS.Color.holiday : (c.weekday == 7 ? DS.Color.saturday : DS.Color.textTertiary))
                        RoundedRectangle(cornerRadius: 2).fill(DS.Color.sea.opacity(Self.tideOpacity(d.tideName))).frame(height: 14)
                            .overlay(Text(String(d.tideName.rawValue.prefix(1))).font(.system(size: 7)).foregroundStyle(.white.opacity(0.9)))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ForEach(months, id: \.self) { m in
                let inMonth = catches.filter { cal.component(.month, from: $0.at) == m }
                let counts = Dictionary(grouping: inMonth, by: \.species).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(4)
                HStack(spacing: DS.Spacing.s) {
                    Text("\(m)月").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).frame(width: 28, alignment: .leading)
                    if counts.isEmpty {
                        Text("まだ釣果なし").font(DS.Font.caption).foregroundStyle(DS.Color.faded)
                    } else {
                        ForEach(Array(counts.enumerated()), id: \.offset) { _, item in
                            Text("\(item.0) \(item.1)").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    static func tideOpacity(_ name: TideName) -> Double {
        switch name {
        case .spring: return 0.95
        case .middle: return 0.6
        case .neap: return 0.3
        case .long: return 0.22
        case .young: return 0.26
        }
    }

    private var heatmap: some View {
        let catches = sessions.flatMap(\.catches)
        let catchMap = card.stats.catchHeatmap
        let lossMap = card.stats.hookLossHeatmap
        let maxCatch = max(1, catchMap.values.max() ?? 1)
        let maxLoss = max(1, lossMap.values.max() ?? 1)
        let cells = Set(catchMap.keys).union(lossMap.keys)
        return Map(initialPosition: .region(MKCoordinateRegion(center: card.spot.coordinate.cl, latitudinalMeters: 500, longitudinalMeters: 500)), interactionModes: [.pan, .zoom]) {
            ForEach(Array(cells), id: \.self) { key in
                if let center = centerOf(key, catches: catches, sessions: sessions) {
                    let c = catchMap[key] ?? 0, l = lossMap[key] ?? 0
                    MapCircle(center: center.cl, radius: 15)
                        .foregroundStyle(c >= l ? DS.Color.accent.opacity(0.25 + 0.6 * Double(c) / Double(maxCatch)) : DS.Color.textTertiary.opacity(0.25 + 0.6 * Double(l) / Double(maxLoss)))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .saturation(0)
    }

    /// メッシュキー → 中心（釣果か針イベントの座標から）
    private func centerOf(_ key: String, catches: [Catch], sessions: [Core.Session]) -> Coordinate? {
        if let c = catches.first(where: { Mesh.key(for: $0.coordinate) == key }) { return Mesh.center(for: c.coordinate) }
        if let e = sessions.flatMap(\.hookEvents).first(where: { Mesh.key(for: $0.coordinate) == key }) { return Mesh.center(for: e.coordinate) }
        return nil
    }

    private func reload() {
        sessions = (try? services.store.sessions(spotID: card.spot.id)) ?? []
        points = (try? services.store.points(spotID: card.spot.id)) ?? []
        rigs = Dictionary(uniqueKeysWithValues: ((try? services.store.rigs()) ?? []).map { ($0.id, $0) })
    }

    private func bars(_ title: String, _ dict: [String: Int]) -> some View {
        let total = max(1, dict.values.reduce(0, +))
        let items = dict.sorted { $0.value > $1.value }.prefix(3)
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            ForEach(Array(items), id: \.key) { k, v in
                HStack(spacing: 4) {
                    Text(k).font(.system(size: 9)).foregroundStyle(DS.Color.textSecondary).frame(width: 40, alignment: .leading).lineLimit(1)
                    GeometryReader { g in Capsule().fill(DS.Color.accent.opacity(0.9)).frame(width: max(2, g.size.width * CGFloat(v) / CGFloat(total)), height: 4) }.frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
