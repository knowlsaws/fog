import SwiftUI
import Charts
import Core

extension GuideEntry: Identifiable {
    public var id: String { species }
}

/// 図鑑（§6）。釣った魚種だけがベストショットのグリッドで並ぶ。この画面だけ縦スクロールを許容する。
struct GuideView: View {
    @Environment(AppServices.self) private var services
    @State private var entries: [GuideEntry] = []
    @State private var sort: GuideEntry.Sort = .maxLength
    @State private var selected: GuideEntry?
    @State private var goCapture = false
    @Environment(\.captureTab) private var captureTab

    private let columns = [GridItem(.flexible(), spacing: DS.Spacing.m), GridItem(.flexible(), spacing: DS.Spacing.m), GridItem(.flexible(), spacing: DS.Spacing.m)]

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            header
            if entries.isEmpty {
                Spacer()
                Button { captureTab?() } label: {
                    Image(systemName: "camera.fill").font(.system(size: 44, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.m) {
                        ForEach(Guide.sorted(entries, by: sort), id: \.species) { e in
                            GuideTile(entry: e, thumbnail: services.store.thumbnail(catchID: e.bestCatchID))
                                .onTapGesture { selected = e }
                        }
                    }
                    .padding(.bottom, DS.Spacing.l)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in reload() }
        .sheet(item: $selected) { SpeciesDetailView(entry: $0).onDisappear(perform: reload) }
    }

    /// 上：魚種数と尾数のチップ、右に並び順。下：見出し「図鑑」（確定画像）
    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.s) {
                countChip(system: "fish.fill", value: entries.count, unit: "種")
                countChip(system: "heart.fill", value: entries.reduce(0) { $0 + $1.count }, unit: "尾")
                Spacer()
                Menu {
                    Button("最大サイズ") { sort = .maxLength }
                    Button("最近") { sort = .recent }
                    Button("尾数") { sort = .count }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.Color.textSecondary).frame(width: 32, height: 32)
                }
            }
            Text("図鑑").font(.system(size: 34, weight: .bold)).foregroundStyle(DS.Color.textPrimary)
        }
        .padding(.top, DS.Spacing.s)
    }

    private func countChip(system: String, value: Int, unit: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 11, weight: .semibold))
            Text("\(value)").font(DS.Font.number(13))
            Text(unit).font(DS.Font.caption)
        }
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(DS.Color.panel, in: Capsule())
    }

    private func reload() {
        let sessions = (try? services.store.sessions()) ?? []
        entries = Guide.entries(sessions: sessions)
    }
}

/// 環境経由で撮影タブへ切り替える（空の状態のカメラアイコン）。
struct CaptureTabKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues { var captureTab: (() -> Void)? { get { self[CaptureTabKey.self] } set { self[CaptureTabKey.self] = newValue } } }

/// タイル：写真（正方形）、魚種名、最大全長。直近 1 週間の記録更新は写真の角にオレンジの点（確定画像のカード型）。
struct GuideTile: View {
    let entry: GuideEntry
    let thumbnail: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail, let ui = UIImage(data: thumbnail) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        ZStack {
                            DS.Color.surfaceRaised
                            Image(systemName: "fish.fill").font(.system(size: 28)).foregroundStyle(DS.Color.faded)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if entry.recentlyUpdated {
                    Circle().fill(DS.Color.accent).frame(width: 10, height: 10).padding(8)
                }
            }
            Text(entry.species).font(.system(size: 14, weight: .medium)).foregroundStyle(DS.Color.textPrimary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(entry.maxLengthCm.map { "\(Int($0.rounded())) cm" } ?? "—").font(DS.Font.number(12)).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 魚種詳細：上半分にベストショット、下半分に数字と条件。写真長押しで魚種・サイズの修正（F-24）。
struct SpeciesDetailView: View {
    let entry: GuideEntry
    @Environment(AppServices.self) private var services
    @State private var catches: [Catch] = []
    @State private var spots: [UUID: Spot] = [:]
    @State private var editing: Catch?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: DS.Spacing.m) {
                ZStack(alignment: .bottomLeading) {
                    if let data = services.store.thumbnail(catchID: entry.bestCatchID), let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else { DS.Color.surface }
                    LinearGradient(colors: [.clear, DS.Color.background], startPoint: .center, endPoint: .bottom)
                    Text(entry.species).font(DS.Font.number(28)).foregroundStyle(DS.Color.textPrimary).padding(DS.Spacing.l)
                }
                .frame(height: geo.size.height * 0.36).clipped()
                HStack(spacing: DS.Spacing.l) {
                    stat(entry.maxLengthCm.map { "\(Int($0.rounded()))" } ?? "—", "cm 最大")
                    stat("\(entry.count)", "尾")
                    stat(entry.firstCaughtAt.formatted(.dateTime.month().day()), "初")
                    stat(entry.lastCaughtAt.formatted(.dateTime.month().day()), "最後")
                }
                .padding(.horizontal, DS.Spacing.l)
                sizeTrend.padding(.horizontal, DS.Spacing.l)
                HStack(spacing: DS.Spacing.m) {
                    distribution("時間帯", entry.conditions.byLight)
                    distribution("潮", entry.conditions.byTide)
                    distribution("水温", Dictionary(uniqueKeysWithValues: entry.conditions.bySeaTemp.map { ("\($0.key)", $0.value) }))
                    distribution("月", Dictionary(uniqueKeysWithValues: entry.conditions.byMonth.map { ("\($0.key)月", $0.value) }))
                }
                .padding(.horizontal, DS.Spacing.l)
                HStack(spacing: DS.Spacing.m) {
                    ForEach(entry.topSpots, id: \.spotID) { s in
                        HStack(spacing: DS.Spacing.xs) {
                            Text(spots[s.spotID]?.name ?? "釣り場").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            Text("\(s.count)").font(DS.Font.number(13)).foregroundStyle(DS.Color.textPrimary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.s) {
                        ForEach(catches, id: \.id) { c in
                            ZStack(alignment: .bottomLeading) {
                                if let data = services.store.thumbnail(catchID: c.id), let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                } else { DS.Color.surface }
                                Text(c.lengthCm.map { "\(Int($0.rounded()))" } ?? "—").font(DS.Font.number(12)).foregroundStyle(DS.Color.textPrimary).padding(4)
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                            .onLongPressGesture { editing = c }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.l)
                }
                .frame(height: 80)
                Spacer(minLength: 0)
            }
        }
        .background(DS.Color.background)
        .onAppear(perform: reload)
        .sheet(item: $editing) { c in CatchEditSheet(catchItem: c) { reload() }.presentationDetents([.medium]) }
    }

    /// サイズの推移（F-41）：計測した釣果を時系列に。自己記録の更新は白い点
    private var sizeTrend: some View {
        let measured = catches.filter { $0.lengthCm != nil }.sorted { $0.at < $1.at }
        var best = 0.0
        let records: Set<UUID> = Set(measured.compactMap { c -> UUID? in
            guard let l = c.lengthCm else { return nil }
            if l > best { best = l; return c.id }
            return nil
        })
        return Group {
            if measured.count >= 2 {
                Chart(measured, id: \.id) { c in
                    LineMark(x: .value("日", c.at), y: .value("cm", c.lengthCm ?? 0)).foregroundStyle(DS.Color.accent.opacity(0.7))
                    PointMark(x: .value("日", c.at), y: .value("cm", c.lengthCm ?? 0))
                        .foregroundStyle(records.contains(c.id) ? Color.white : DS.Color.accent).symbolSize(records.contains(c.id) ? 40 : 20)
                }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(DS.Color.textTertiary) } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()).font(.system(size: 9)).foregroundStyle(DS.Color.textTertiary) } }
                .frame(height: 64)
            } else {
                Text("サイズを 2 尾以上計測すると推移が出ます").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func reload() {
        let sessions = (try? services.store.sessions()) ?? []
        catches = sessions.flatMap(\.catches).filter { $0.species == entry.species }.sorted { $0.at > $1.at }
        spots = Dictionary(uniqueKeysWithValues: ((try? services.store.spots()) ?? []).map { ($0.id, $0) })
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DS.Font.number(22)).foregroundStyle(DS.Color.textPrimary)
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 小さな分布バー（横並び）
    private func distribution(_ title: String, _ dict: [String: Int]) -> some View {
        let total = max(1, dict.values.reduce(0, +))
        let items = dict.sorted { $0.value > $1.value }.prefix(4)
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            ForEach(Array(items), id: \.key) { k, v in
                HStack(spacing: 4) {
                    Text(k).font(.system(size: 9)).foregroundStyle(DS.Color.textSecondary).frame(width: 36, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        Capsule().fill(DS.Color.accent.opacity(0.9)).frame(width: max(2, g.size.width * CGFloat(v) / CGFloat(total)), height: 4)
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 魚種・サイズの修正。修正は判定モデルの補正に使う（F-24）。
struct CatchEditSheet: View {
    let catchItem: Catch
    let onDone: () -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var species: String = ""
    @State private var lengthText: String = ""
    @State private var deleting: Catch?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("修正").font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Button(role: .destructive) { deleting = catchItem } label: {
                    Label("この釣果を削除", systemImage: "trash").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.s) {
                    ForEach(Species.initialCatalog) { s in
                        Button { species = s.name } label: {
                            Text(s.name).font(DS.Font.label)
                                .foregroundStyle(species == s.name ? DS.Color.background : DS.Color.textPrimary)
                                .padding(.horizontal, DS.Spacing.m).padding(.vertical, DS.Spacing.xs)
                                .background(species == s.name ? DS.Color.accent : DS.Color.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("全長 cm", text: $lengthText).keyboardType(.decimalPad)
                    .font(DS.Font.number(20)).foregroundStyle(DS.Color.textPrimary)
                    .padding(DS.Spacing.m).background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip))
                Text("cm").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Button {
                services.capture.setSpecies(catchID: catchItem.id, species: species, corrected: species != catchItem.species)
                if let l = Double(lengthText), l != catchItem.lengthCm { services.capture.setLength(catchID: catchItem.id, lengthCm: l) }
                onDone(); dismiss()
            } label: {
                Text("保存").font(DS.Font.label).foregroundStyle(DS.Color.background)
                    .frame(maxWidth: .infinity).padding(DS.Spacing.m).background(DS.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(DS.Spacing.l)
        .background(DS.Color.background)
        .onAppear { species = catchItem.species; lengthText = catchItem.lengthCm.map { String(Int($0.rounded())) } ?? "" }
        .catchDeleteDialog(item: $deleting) { _ in onDone(); dismiss() }
    }
}

/// 釣果の削除ダイアログ：記録だけ消すか、フォトライブラリの写真も消すか。
struct CatchDeleteDialog: ViewModifier {
    @Binding var item: Catch?
    let onDeleted: (Catch) -> Void
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        content.confirmationDialog("この釣果を削除", isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }), titleVisibility: .visible) {
            Button("記録だけ削除", role: .destructive) { run(deletePhoto: false) }
            Button("写真ライブラリからも削除", role: .destructive) { run(deletePhoto: true) }
            Button("キャンセル", role: .cancel) { item = nil }
        } message: {
            Text("削除した釣果は分析からも外れます")
        }
    }

    private func run(deletePhoto: Bool) {
        guard let c = item else { return }
        item = nil
        Task { @MainActor in
            await services.capture.deleteCatch(id: c.id, deletePhoto: deletePhoto)
            onDeleted(c)
        }
    }
}

extension View {
    func catchDeleteDialog(item: Binding<Catch?>, onDeleted: @escaping (Catch) -> Void) -> some View {
        modifier(CatchDeleteDialog(item: item, onDeleted: onDeleted))
    }
}
