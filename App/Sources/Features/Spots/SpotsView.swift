import SwiftUI
import MapKit
import Core

/// 釣り場（§7）。全画面のモノトーン地図に釣り場を点で置き、下にカードを横並べ。カードを送ると地図が追従する。
struct SpotsView: View {
    @Environment(AppServices.self) private var services
    @State private var model = SpotsViewModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedID: UUID?
    @State private var detail: SpotsViewModel.Card?
    @State private var searchText = ""
    @State private var showSearch = false
    /// 表示範囲の緯度幅（度）。狭いほど拡大している
    @State private var latitudeSpan: Double = 0.1

    var body: some View {
        ZStack(alignment: .bottom) {
            map.ignoresSafeArea(edges: .top)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: DS.Spacing.s) {
                        roundButton("magnifyingglass") { showSearch = true }
                        roundButton("location.fill") { if let c = model.currentLocation { camera = .region(MKCoordinateRegion(center: c.cl, latitudinalMeters: 3000, longitudinalMeters: 3000)) } }
                    }
                    .padding(DS.Spacing.l)
                }
                Spacer()
            }
            cards
        }
        .onAppear {
            model.attach(services)
            if let first = model.cards.first(where: { $0.spot.coordinate.isPlausible }) {
                selectedID = first.spot.id
                camera = .region(region(for: first.spot.coordinate))
            } else if let c = model.currentLocation {
                camera = .region(MKCoordinateRegion(center: c.cl, latitudinalMeters: 8000, longitudinalMeters: 8000))
            } else {
                camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 41.77, longitude: 140.73), latitudinalMeters: 20_000, longitudinalMeters: 20_000))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in model.refresh() }
        .onChange(of: selectedID) { _, id in
            if let id, let c = model.allCards.first(where: { $0.spot.id == id }), c.spot.coordinate.isPlausible { withAnimation { camera = .region(region(for: c.spot.coordinate)) } }
        }
        .sheet(item: $detail) { SpotDetailView(card: $0).onDisappear { model.refresh() } }
        .sheet(isPresented: $showSearch) { SpotSearchSheet { item in
            showSearch = false
            camera = .region(MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
            model.addCandidate(name: item.name ?? "釣り場", coordinate: Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
        } }
    }

    private func region(for c: Coordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(center: c.cl, latitudinalMeters: 4000, longitudinalMeters: 4000)
    }

    /// 拡大しているときは各点にホームと同じ釣れ率の円を出す（緯度幅 0.12° ≈ 13 km 未満）
    private var zoomedIn: Bool { latitudeSpan < 0.12 }

    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(model.allCards.filter { $0.spot.coordinate.isPlausible }) { card in
                Annotation("", coordinate: card.spot.coordinate.cl, anchor: .center) {
                    Button { selectedID = card.spot.id } label: {
                        SpotMarker(card: card, selected: selectedID == card.spot.id, zoomedIn: zoomedIn)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let c = model.currentLocation {
                Annotation("", coordinate: c.cl, anchor: .center) {
                    Circle().fill(.white).frame(width: 10, height: 10).overlay(Circle().stroke(DS.Color.background, lineWidth: 2))
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            latitudeSpan = context.region.span.latitudeDelta
            model.searchPorts(in: context.region)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(0)
        .contrast(0.9)
        .mapControlVisibility(.hidden)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.Color.textPrimary)
                .frame(width: 44, height: 44).background(DS.Color.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 画面下 3 割：横スクロール、近い順。
    private var cards: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.m) {
                        ForEach(model.allCards) { card in
                            SpotCardView(card: card, selected: selectedID == card.spot.id,
                                         onSelectHome: { model.selectForHome(card.spot) },
                                         onRegister: { model.register(card) })
                                .frame(width: 230)
                                .onTapGesture {
                                    if selectedID == card.spot.id { if !card.isCandidate { detail = card } } else { selectedID = card.spot.id }
                                }
                        }
                        if model.allCards.isEmpty {
                            Text("地図を動かすと近くの漁港が出ます").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).padding()
                        }
                    }
                    .padding(.horizontal, DS.Spacing.l)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID)
                .frame(height: geo.size.height * 0.30)
                .padding(.bottom, 96)
            }
        }
    }
}

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// カード：釣り場名、今の釣れ率（0〜100）、釣行数、最後の釣行日、よく釣れる魚種。
struct SpotCardView: View {
    let card: SpotsViewModel.Card
    let selected: Bool
    let onSelectHome: () -> Void
    var onRegister: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(card.spot.name).font(.system(size: 18, weight: .bold)).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Spacer()
                if card.isCandidate {
                    Button(action: onRegister) {
                        Label("登録", systemImage: "plus").font(DS.Font.caption).foregroundStyle(DS.Color.background)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(DS.Color.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSelectHome) {
                        Text("選択").font(DS.Font.caption).foregroundStyle(DS.Color.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(DS.Color.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("釣れ率").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            Text("\(card.score)").font(DS.Font.score(40)).foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: DS.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "fish.fill").font(.system(size: 11)).foregroundStyle(DS.Color.textTertiary)
                        Text(card.isCandidate ? "未登録" : "\(card.stats.catches)").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                    if let last = card.stats.lastSessionAt {
                        Text(last, format: .dateTime.year().month().day()).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    } else {
                        Text(card.isCandidate ? "地図から見つけた漁港" : (card.spot.coordinate.isPlausible ? "\(card.stats.sessions)釣行" : "位置なしで撮影した釣果。詳細から削除できます")).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(card.stats.topSpecies.prefix(2), id: \.species) { s in
                        HStack(spacing: 3) {
                            Text(s.species).font(.system(size: 9)).foregroundStyle(DS.Color.textTertiary)
                            Image(systemName: "fish.fill").font(.system(size: 11)).foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.m)
        .background(selected ? DS.Color.surfaceRaised : DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// 検索（全国の地名・漁港名）。
struct SpotSearchSheet: View {
    let onPick: (MKMapItem) -> Void
    @State private var text = ""
    @State private var results: [MKMapItem] = []

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            TextField("地名・漁港名", text: $text)
                .font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                .padding(DS.Spacing.m).background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip))
                .onSubmit { Task { await search() } }
            ScrollView {
                VStack(spacing: DS.Spacing.s) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button { onPick(item) } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "").font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                                Text(item.placemark.title ?? "").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Spacing.m).background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.chip))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(DS.Spacing.l)
        .background(DS.Color.background)
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38, longitude: 137), latitudinalMeters: 2_000_000, longitudinalMeters: 2_000_000)
        results = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
    }
}

/// 地図の点。引いているときは釣行数で大きさが変わる点（登録はオレンジ、未登録はグレー）に釣行数の小さな数字、
/// 拡大しているときはホームと同じ釣れ率の円（数字と円弧）。
struct SpotMarker: View {
    let card: SpotsViewModel.Card
    let selected: Bool
    let zoomedIn: Bool

    private var color: Color { card.spot.isRegistered ? DS.Color.accent : DS.Color.textTertiary }

    var body: some View {
        if zoomedIn {
            VStack(spacing: 2) {
                ZStack {
                    Circle().fill(DS.Color.background.opacity(0.85)).frame(width: 44, height: 44)
                    Circle().stroke(DS.Color.faded, lineWidth: 4).frame(width: 38, height: 38)
                    Circle().trim(from: 0, to: CGFloat(max(0, min(100, card.score))) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 38, height: 38)
                    Text("\(card.score)").font(DS.Font.number(15)).foregroundStyle(DS.Color.textPrimary)
                }
                .scaleEffect(selected ? 1.15 : 1)
                Text(card.spot.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(DS.Color.background.opacity(0.7), in: Capsule())
            }
        } else {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(selected ? 1 : 0.85)
                    .overlay(selected ? Circle().stroke(.white, lineWidth: 2) : nil)
                if card.stats.sessions > 0 {
                    Text("\(card.stats.sessions)").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
    }

    private var dotSize: CGFloat {
        card.isCandidate ? 10 : 14 + CGFloat(min(12, card.stats.sessions)) * 1.6
    }
}
