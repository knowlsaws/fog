import SwiftUI
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

    private let columns = [GridItem(.flexible(), spacing: DS.Spacing.s), GridItem(.flexible(), spacing: DS.Spacing.s), GridItem(.flexible(), spacing: DS.Spacing.s)]

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
                    LazyVGrid(columns: columns, spacing: DS.Spacing.s) {
                        ForEach(Guide.sorted(entries, by: sort), id: \.species) { e in
                            GuideTile(entry: e, thumbnail: services.store.thumbnail(catchID: e.bestCatchID))
                                .onTapGesture { selected = e }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in reload() }
        .sheet(item: $selected) { SpeciesDetailView(entry: $0).onDisappear(perform: reload) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(entries.count)").font(DS.Font.number(24)).foregroundStyle(DS.Color.textPrimary)
            Text("種").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            Text("\(entries.reduce(0) { $0 + $1.count })").font(DS.Font.number(24)).foregroundStyle(DS.Color.textPrimary)
            Text("尾").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            Spacer()
            Menu {
                Button("最大サイズ") { sort = .maxLength }
                Button("最近") { sort = .recent }
                Button("尾数") { sort = .count }
            } label: {
                Image(systemName: sort == .maxLength ? "ruler" : (sort == .recent ? "clock" : "number")).font(.system(size: 16)).foregroundStyle(DS.Color.textSecondary)
            }
        }
        .frame(height: 44)
    }

    private func reload() {
        let sessions = (try? services.store.sessions()) ?? []
        entries = Guide.entries(sessions: sessions)
    }
}

/// 環境経由で撮影タブへ切り替える（空の状態のカメラアイコン）。
struct CaptureTabKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues { var captureTab: (() -> Void)? { get { self[CaptureTabKey.self] } set { self[CaptureTabKey.self] = newValue } } }

struct GuideTile: View {
    let entry: GuideEntry
    let thumbnail: Data?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumbnail, let ui = UIImage(data: thumbnail) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                DS.Color.surface
                Image(systemName: "fish.fill").font(.system(size: 28)).foregroundStyle(DS.Color.faded).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, DS.Color.background.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.species).font(DS.Font.caption).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text(entry.maxLengthCm.map { "\(Int($0.rounded()))cm" } ?? "—").font(DS.Font.number(13)).foregroundStyle(DS.Color.textSecondary)
            }
            .padding(DS.Spacing.s)
            if entry.recentlyUpdated {
                VStack { HStack { Spacer(); Circle().fill(DS.Color.accent).frame(width: 8, height: 8).padding(DS.Spacing.s) }; Spacer() }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
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
                .frame(height: geo.size.height * 0.45).clipped()
                HStack(spacing: DS.Spacing.l) {
                    stat(entry.maxLengthCm.map { "\(Int($0.rounded()))" } ?? "—", "cm 最大")
                    stat("\(entry.count)", "尾")
                    stat(entry.firstCaughtAt.formatted(.dateTime.month().day()), "初")
                    stat(entry.lastCaughtAt.formatted(.dateTime.month().day()), "最後")
                }
                .padding(.horizontal, DS.Spacing.l)
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("修正").font(DS.Font.label).foregroundStyle(DS.Color.textTertiary)
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
    }
}
