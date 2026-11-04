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

    var body: some View {
        ZStack(alignment: .bottom) {
            map
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
        .ignoresSafeArea(edges: .top)
        .onAppear { model.attach(services); if let first = model.cards.first { selectedID = first.spot.id; camera = .region(region(for: first.spot.coordinate)) } }
        .onReceive(NotificationCenter.default.publisher(for: .fogStoreDidChange)) { _ in model.refresh() }
        .onChange(of: selectedID) { _, id in
            if let id, let c = model.cards.first(where: { $0.spot.id == id }) { withAnimation { camera = .region(region(for: c.spot.coordinate)) } }
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

    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(model.cards) { card in
                Annotation("", coordinate: card.spot.coordinate.cl, anchor: .center) {
                    Button { selectedID = card.spot.id } label: {
                        ZStack {
                            Circle()
                                .fill(card.spot.isRegistered ? DS.Color.accent : DS.Color.textTertiary)
                                .frame(width: dotSize(card), height: dotSize(card))
                                .opacity(selectedID == card.spot.id ? 1 : 0.8)
                            Text("\(card.score)").font(DS.Font.number(10)).foregroundStyle(DS.Color.background)
                        }
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
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(0)
        .contrast(0.9)
        .mapControlVisibility(.hidden)
    }

    private func dotSize(_ card: SpotsViewModel.Card) -> CGFloat {
        18 + CGFloat(min(12, card.stats.sessions)) * 1.6
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.Color.textPrimary)
                .frame(width: 40, height: 40).background(DS.Color.surface.opacity(0.9), in: Circle())
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
                        ForEach(model.cards) { card in
                            SpotCardView(card: card, selected: selectedID == card.spot.id, onSelectHome: { model.selectForHome(card.spot) })
                                .frame(width: 230)
                                .onTapGesture { if selectedID == card.spot.id { detail = card } else { selectedID = card.spot.id } }
                        }
                        if model.cards.isEmpty {
                            Text("釣行が始まると釣り場が登録されます").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).padding()
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.spot.name).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Spacer()
                Text("\(card.score)").font(DS.Font.score(34)).foregroundStyle(DS.Color.accent)
            }
            HStack(spacing: DS.Spacing.m) {
                Text("\(card.stats.sessions)釣行").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                if let last = card.stats.lastSessionAt {
                    Text(last, format: .dateTime.month().day()).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                ForEach(card.stats.topSpecies.prefix(3), id: \.species) { s in
                    Text(s.species.prefix(2)).font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Color.background)
                        .frame(width: 22, height: 22).background(DS.Color.secondary, in: Circle())
                }
            }
            HStack {
                if !card.spot.isRegistered {
                    Text("未登録").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                Button(action: onSelectHome) {
                    Text("選択").font(DS.Font.caption).foregroundStyle(DS.Color.textPrimary)
                        .padding(.horizontal, DS.Spacing.m).padding(.vertical, 4).background(DS.Color.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.m)
        .background(selected ? DS.Color.surfaceRaised : DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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
