import SwiftUI
import MapKit
import Charts
import Core

/// 釣行詳細：時系列に釣果と条件の推移、立ち位置の軌跡、レポート。
struct SessionDetailView: View {
    let session: Core.Session
    let spotName: String
    @Environment(AppServices.self) private var services
    @State private var deleting: Catch?
    @State private var removedIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    Text(spotName).font(DS.Font.number(22)).foregroundStyle(DS.Color.textPrimary)
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute()).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    Spacer()
                    Text(session.isBlank ? "ボウズ" : "\(session.catches.count)尾").font(DS.Font.number(18)).foregroundStyle(session.isBlank ? DS.Color.textTertiary : DS.Color.accent)
                }
                if let r = session.report {
                    Text(r.summary).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                    Text(r.body).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                timeline
                track
                catches
            }
            .padding(DS.Spacing.l)
        }
        .background(DS.Color.background)
    }

    /// 条件の推移（潮位・風・気圧）と釣れた時刻
    private var timeline: some View {
        Chart {
            ForEach(session.snapshots, id: \.id) { s in
                if let t = s.tideLevelCm { LineMark(x: .value("時刻", s.at), y: .value("潮位", t), series: .value("系列", "潮位")).foregroundStyle(DS.Color.textSecondary) }
            }
            ForEach(session.catches, id: \.id) { c in
                RuleMark(x: .value("釣果", c.at)).foregroundStyle(DS.Color.accent).lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top) { Text(c.species).font(DS.Font.caption).foregroundStyle(DS.Color.accent) }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks(values: .stride(by: .hour)) { _ in AxisValueLabel(format: .dateTime.hour()).foregroundStyle(DS.Color.textTertiary) } }
        .frame(height: 120)
    }

    /// 立ち位置の軌跡（モノトーン地図）
    private var track: some View {
        let coords = session.track.map { CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        return Group {
            if coords.count >= 1 {
                Map(initialPosition: .region(MKCoordinateRegion(center: coords[coords.count / 2], latitudinalMeters: 600, longitudinalMeters: 600)), interactionModes: []) {
                    if coords.count >= 2 { MapPolyline(coordinates: coords).stroke(DS.Color.accent, lineWidth: 3) }
                    ForEach(session.catches, id: \.id) { c in
                        Annotation(c.species, coordinate: CLLocationCoordinate2D(latitude: c.coordinate.latitude, longitude: c.coordinate.longitude)) {
                            Circle().fill(DS.Color.accent).frame(width: 10, height: 10)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .saturation(0)
            }
        }
    }

    /// 釣果の一覧。長押しで削除（記録だけ／写真も）。
    private var catches: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ForEach(session.catches.filter { !removedIDs.contains($0.id) }, id: \.id) { c in
                HStack(spacing: DS.Spacing.m) {
                    if let data = services.store.thumbnail(catchID: c.id), let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip))
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.chip).fill(DS.Color.surface).frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.Spacing.s) {
                            Text(c.at, format: .dateTime.hour().minute()).font(DS.Font.number(14)).foregroundStyle(DS.Color.textSecondary)
                            Text(c.species).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                        }
                        HStack(spacing: DS.Spacing.s) {
                            Text(c.lengthCm.map { "\(Int($0.rounded()))cm" } ?? "未計測").font(DS.Font.number(14)).foregroundStyle(c.lengthCm == nil ? DS.Color.textTertiary : DS.Color.accent)
                            if let e = c.env {
                                Text([e.tideName, e.tideRateCmPerHour.map { $0 > 0 ? "上げ" : "下げ" }, e.windSpeedMS.map { "\(Int($0.rounded()))m/s" }].compactMap { $0 }.joined(separator: " "))
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onLongPressGesture { deleting = c }
            }
        }
        .catchDeleteDialog(item: $deleting) { removedIDs.insert($0.id) }
    }
}

/// 分析の全画面：魚種別の切替、水温・風・気圧傾向との相関、タックル・リグ別。
struct AnalysisDetailView: View {
    let kind: LogView.AnalysisKind
    let sessions: [Core.Session]
    let spots: [UUID: Spot]
    @State private var species: String = ""

    private var allCatches: [Catch] { sessions.flatMap(\.catches) }
    private var speciesList: [String] { Array(Set(allCatches.map(\.species))).sorted() }
    private var catches: [Catch] { species.isEmpty ? allCatches : allCatches.filter { $0.species == species } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.s) {
                        chip("全部", selected: species.isEmpty) { species = "" }
                        ForEach(speciesList, id: \.self) { s in chip(s, selected: species == s) { species = s } }
                    }
                }
                switch kind {
                case .hour:
                    let cells = Analytics.catchesByHour(catches: catches)
                    bars("時間帯別", (0..<24).map { ("\($0)", Double(cells[$0] ?? 0)) }, labelsEvery: 6)
                    let months = Analytics.catchesByMonth(catches: catches)
                    bars("月別", months.map { ("\($0.month)月", Double($0.count)) }, labelsEvery: 1)
                case .tide:
                    let d = Analytics.conditionDistribution(of: catches)
                    bars("上げ・下げ", ["上げ", "下げ", "潮止まり"].map { ($0, Double(d.byTide[$0] ?? 0)) }, labelsEvery: 1)
                    bars("潮名", ["大潮", "中潮", "小潮", "長潮", "若潮"].map { ($0, Double(d.byTideName[$0] ?? 0)) }, labelsEvery: 1)
                    bars("水温", d.bySeaTemp.keys.sorted().map { ("\($0)℃", Double(d.bySeaTemp[$0] ?? 0)) }, labelsEvery: 1)
                    bars("風", ["微風", "そよ風", "強風"].map { ($0, Double(d.byWind[$0] ?? 0)) }, labelsEvery: 1)
                    bars("気圧傾向", ["下降", "安定", "上昇"].map { ($0, Double(d.byPressureTrend[$0] ?? 0)) }, labelsEvery: 1)
                case .spot:
                    let stats = Analytics.statsBySpot(sessions: sessions)
                    bars("釣行 1 時間あたり尾数", stats.map { (spots[$0.key]?.name ?? "釣り場", $0.value.catchesPerHour) }.sorted { $0.1 > $1.1 }, labelsEvery: 1)
                    bars("ボウズ率", stats.map { (spots[$0.key]?.name ?? "釣り場", $0.value.blankRate * 100) }.sorted { $0.1 < $1.1 }, labelsEvery: 1)
                    let rigs = Analytics.rigStats(sessions: sessions)
                    bars("リグ別 釣果", rigs.map { ($0.rigID?.uuidString.prefix(4).description ?? "未設定", Double($0.catches)) }, labelsEvery: 1)
                    bars("リグ別 ロスト", rigs.map { ($0.rigID?.uuidString.prefix(4).description ?? "未設定", Double($0.hookLosses)) }, labelsEvery: 1)
                }
            }
            .padding(DS.Spacing.l)
        }
        .background(DS.Color.background)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(DS.Font.label).foregroundStyle(selected ? DS.Color.background : DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.m).padding(.vertical, DS.Spacing.xs)
                .background(selected ? DS.Color.accent : DS.Color.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func bars(_ title: String, _ data: [(String, Double)], labelsEvery: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            Chart(Array(data.enumerated()), id: \.offset) { i, item in
                BarMark(x: .value("x", item.0), y: .value("y", item.1)).foregroundStyle(DS.Color.accent)
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { v in if v.index % labelsEvery == 0 { AxisValueLabel().font(.system(size: 9)).foregroundStyle(DS.Color.textTertiary) } } }
            .frame(height: 100)
        }
    }
}
