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
                    heatmap.frame(height: geo.size.height * 0.5)
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
                }
                .padding(.horizontal, DS.Spacing.l)
                Spacer(minLength: 0)
            }
        }
        .background(DS.Color.background)
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
