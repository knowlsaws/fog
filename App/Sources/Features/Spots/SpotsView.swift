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
    @State private var showCompare = false
    /// 表示範囲の緯度幅（度）。狭いほど拡大している
    @State private var latitudeSpan: Double = 0.1
    // 地図レイヤー（F-43）
    @State private var layersOn = false
    @State private var layer: MapLayer = .wind
    @State private var hourOffset = 0
    @State private var raster: FieldRaster?
    @State private var particles = ParticleSystem(count: MapLayerSettings.density.count)
    @State private var region: MKCoordinateRegion?
    @State private var showLayerSettings = false
    // 釣果情報のピン（F-44）
    /// 既定で表示（2026-11-05 開発者の指示）。オフにしたら覚える
    @State private var feedPinsOn = UserDefaults.standard.object(forKey: "fog.feedPins.on") as? Bool ?? true
    @State private var feedPins: [FeedCatchExtractor.Pin] = []
    @State private var feedPin: FeedCatchExtractor.Pin?
    @State private var rasterTask: Task<Void, Never>?
    /// 時刻ごとの色面（同じ層・同じ範囲・同じ版の間だけ有効）。時刻バーを戻しても即座に出る
    @State private var rasterCache: [Int: FieldRaster] = [:]
    @State private var rasterCacheKey = ""
    static let layerHours = 71

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                map.overlay {
                    if layersOn { MapLayersOverlay(proxy: proxy, raster: raster, particles: particles, animate: layer.vector != nil && MapLayerSettings.particles) }
                }
            }
            .ignoresSafeArea(edges: .top)
            VStack {
                HStack(alignment: .top) {
                    if layersOn {
                        MapLayersControls(layer: $layer, hourOffset: $hourOffset, start: layerStart, hours: Self.layerHours,
                                          loading: services.gridForecast.loading, error: services.gridForecast.lastError, onSettings: { showLayerSettings = true })
                            .padding(.leading, DS.Spacing.l).padding(.top, DS.Spacing.l)
                    }
                    Spacer()
                    VStack(spacing: DS.Spacing.s) {
                        roundButton("magnifyingglass") { showSearch = true }
                        roundButton("list.number") { showCompare = true }
                        roundButton(layersOn ? "square.3.layers.3d.top.filled" : "square.3.layers.3d") { toggleLayers() }
                        roundButton(feedPinsOn ? "fish.fill" : "fish") { toggleFeedPins() }
                        roundButton("location.fill") { if let c = model.currentLocation { camera = .region(MKCoordinateRegion(center: c.cl, latitudinalMeters: 3000, longitudinalMeters: 3000)) } }
                    }
                    .padding(DS.Spacing.l)
                }
                Spacer()
            }
            cards
        }
        .onChange(of: layer) { _, _ in rebuildRaster() }
        .sheet(isPresented: $showLayerSettings, onDismiss: {
            particles = ParticleSystem(count: MapLayerSettings.density.count)
            if !MapLayerSettings.isEnabled(layer), let first = MapLayerSettings.enabled.first { layer = first }
            rebuildRaster()
        }) { NavigationStack { MapLayerSettingsView() }.preferredColorScheme(.dark).tint(DS.Color.accent) }
        .onChange(of: hourOffset) { _, _ in rebuildRaster(throttle: true) }
        .onChange(of: services.gridForecast.version) { _, _ in rebuildRaster() }
        .onAppear {
            model.attach(services)
            if feedPinsOn { feedPins = model.feedPins() }
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
        .sheet(isPresented: $showCompare) { SpotCompareSheet(model: model).presentationDetents([.large]) }
        .sheet(item: $feedPin) { FeedPinSheet(pin: $0).presentationDetents([.medium, .large]) }
        .onChange(of: services.feeds.items.count) { _, _ in if feedPinsOn { feedPins = model.feedPins() } }
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
                    // 同じ場所の釣果情報は点の上に載せる（重なって隠れないように。2026-11-05 実機フィードバック）
                    .overlay(alignment: .top) {
                        if let p = feedPin(for: card) {
                            Button { feedPin = p } label: { FeedPinMarker(pin: p) }.buttonStyle(.plain)
                                .offset(y: zoomedIn ? -40 : -24)
                        }
                    }
                }
            }
            if let c = model.currentLocation {
                Annotation("", coordinate: c.cl, anchor: .center) {
                    Circle().fill(.white).frame(width: 10, height: 10).overlay(Circle().stroke(DS.Color.background, lineWidth: 2))
                }
            }
            // RSS の記事から拾った釣果（F-44）：場所ごとに 1 つ。新しいほど濃い。釣り場の点と同じ場所のものは点の上に載せる（上）
            if feedPinsOn {
                ForEach(standalonePins) { pin in
                    Annotation("", coordinate: pin.coordinate.cl, anchor: .bottom) {
                        Button { feedPin = pin } label: { FeedPinMarker(pin: pin) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            latitudeSpan = context.region.span.latitudeDelta
            region = context.region
            model.searchPorts(in: context.region)
            if layersOn {
                ensureTiles(for: context.region)
                // 読み込み済みの範囲の中なら作り直さない（枠が動かない）。外に出たら作り直す
                if let r = raster, !r.box.contains(region: context.region) { rebuildRaster() } else if raster == nil { rebuildRaster() }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(0)
        .contrast(0.9)
        .mapControlVisibility(.hidden)
    }

    // MARK: 釣果情報のピン（F-44）

    /// 釣り場の点（登録済み・候補）と同じ場所（80 m 以内）の釣果情報
    private func feedPin(for card: SpotsViewModel.Card) -> FeedCatchExtractor.Pin? {
        guard feedPinsOn else { return nil }
        return feedPins.first { Geo.distanceMeters($0.coordinate, card.spot.coordinate) < 80 }
    }

    /// 釣り場の点が無い場所の釣果情報だけ、単独のピンにする
    private var standalonePins: [FeedCatchExtractor.Pin] {
        let cards = model.allCards.filter { $0.spot.coordinate.isPlausible }
        return feedPins.filter { p in !cards.contains { Geo.distanceMeters($0.spot.coordinate, p.coordinate) < 80 } }
    }

    private func toggleFeedPins() {
        feedPinsOn.toggle()
        UserDefaults.standard.set(feedPinsOn, forKey: "fog.feedPins.on")
        guard feedPinsOn else { feedPins = []; return }
        feedPins = model.feedPins()
        Task { await services.feeds.refreshIfNeeded() }
    }

    // MARK: 地図レイヤー（F-43）

    /// 時刻バーの起点：今の時刻を 1 時間に切り下げ
    private var layerStart: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let c = cal.dateComponents([.year, .month, .day, .hour], from: Date())
        return cal.date(from: c) ?? Date()
    }

    private func toggleLayers() {
        layersOn.toggle()
        guard layersOn else { raster = nil; return }
        MapLayerSettings.usedOnce = true
        if !MapLayerSettings.isEnabled(layer), let first = MapLayerSettings.enabled.first { layer = first }
        if let region {
            ensureTiles(for: region)
        } else if let c = model.currentLocation ?? model.cards.first?.spot.coordinate {
            services.gridForecast.ensure(minLat: c.latitude - 0.2, maxLat: c.latitude + 0.2, minLon: c.longitude - 0.25, maxLon: c.longitude + 0.25)
        }
        rebuildRaster()
    }

    /// 表示範囲＋周り 1 周のタイルを用意する
    private func ensureTiles(for region: MKCoordinateRegion) {
        let half = region.span.latitudeDelta / 2, halfLon = region.span.longitudeDelta / 2
        services.gridForecast.ensure(minLat: region.center.latitude - half, maxLat: region.center.latitude + half,
                                     minLon: region.center.longitude - halfLon, maxLon: region.center.longitude + halfLon)
    }

    /// 読み込み済みタイル全体（表示範囲の周り 1 周を含む）に対して色面と流れの格子を作る。裏で計算して差し替える。
    /// 時刻バーをドラッグ中は 80 ms 待ってから（連続で作らない）。作ったものは時刻ごとに取っておく
    private func rebuildRaster(throttle: Bool = false) {
        guard layersOn, let region, let grid = services.gridForecast.mosaic(marine: layer.isMarine), !grid.isEmpty,
              let lat = grid.latitudeRange, let lon = grid.longitudeRange else { raster = nil; return }
        // 表示範囲の 3 倍までに絞る（遠くまで読み込んでいても画像が巨大にならないように）
        let half = region.span.latitudeDelta * 1.5, halfLon = region.span.longitudeDelta * 1.5
        var box = GeoBox(minLat: max(lat.lowerBound, region.center.latitude - half), maxLat: min(lat.upperBound, region.center.latitude + half),
                         minLon: max(lon.lowerBound, region.center.longitude - halfLon), maxLon: min(lon.upperBound, region.center.longitude + halfLon))
        // 表示が今の色面の中にあるなら、箱はそのまま（時刻だけ変える。キャッシュが効く）
        if let r = raster, r.layer == layer, r.box.contains(region: region) { box = r.box }
        guard box.maxLat > box.minLat, box.maxLon > box.minLon else { raster = nil; return }
        let key = "\(layer.rawValue)|\(services.gridForecast.version)|\(box.minLat),\(box.maxLat),\(box.minLon),\(box.maxLon)|\(MapLayerSettings.opacity)"
        if key != rasterCacheKey { rasterCache = [:]; rasterCacheKey = key }
        if let cached = rasterCache[hourOffset] { raster = cached; return }
        let time = layerStart.addingTimeInterval(Double(hourOffset) * 3600)
        let l = layer, opacity = MapLayerSettings.opacity, hour = hourOffset
        // 画素数は 1° あたり 200（上限 520）。描くときに滑らかに拡大される
        let width = min(520, max(100, Int((box.maxLon - box.minLon) * 200))), height = min(520, max(100, Int((box.maxLat - box.minLat) * 260)))
        rasterTask?.cancel()
        let b = box
        rasterTask = Task.detached(priority: .userInitiated) {
            if throttle { try? await Task.sleep(nanoseconds: 80_000_000) }
            guard !Task.isCancelled else { return }
            let r = FieldRaster.build(grid: grid, layer: l, time: time, box: b, opacity: opacity, width: width, height: height)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                raster = r
                if rasterCache.count > 24 { rasterCache = [:] }
                rasterCache[hour] = r
            }
        }
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
                if layersOn {
                    MapTimeBar(hourOffset: $hourOffset, start: layerStart, hours: Self.layerHours)
                        .frame(height: 40).padding(.horizontal, DS.Spacing.l).padding(.bottom, DS.Spacing.s)
                }
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
                .padding(.bottom, DS.Spacing.m)
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

/// 釣り場の比較（F-30）：登録した釣り場を、選んだ日の最高釣れ率の順に並べる。日は矢印で送る（今日から 2 週間）。
/// 行をタップするとホームの釣り場にする
struct SpotCompareSheet: View {
    let model: SpotsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var dayOffset = 0
    @State private var rows: [SpotsViewModel.CompareRow] = []
    @State private var loading = false
    private let tz = TimeZone(identifier: "Asia/Tokyo") ?? .current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Button { if dayOffset > 0 { dayOffset -= 1 } } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(dayOffset > 0 ? DS.Color.textSecondary : DS.Color.faded).frame(width: 28, height: 22) }.buttonStyle(.plain)
                Spacer()
                HStack(spacing: 6) {
                    Text(ForecastChart.dayLabel(day, timeZone: tz)).font(DS.Font.number(16)).foregroundStyle(DS.Color.textPrimary)
                    Text(dayOffset == 0 ? "今日" : (dayOffset == 1 ? "明日" : "")).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                Button { if dayOffset < 13 { dayOffset += 1 } } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(dayOffset < 13 ? DS.Color.textSecondary : DS.Color.faded).frame(width: 28, height: 22) }.buttonStyle(.plain)
            }
            if rows.isEmpty {
                Text(loading ? "計算中" : "登録した釣り場がありません").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            VStack(spacing: DS.Spacing.s) {
                ForEach(rows) { r in
                    Button { model.selectForHome(r.spot); dismiss() } label: { row(r) }.buttonStyle(.plain)
                }
            }
            Spacer()
            Text("タップでホームの釣り場にする · 予報の先は潮と光だけで計算").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
        .task(id: dayOffset) {
            loading = true
            rows = await model.compare(dayOffset: dayOffset)
            loading = false
        }
    }

    private var day: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.startOfDay(for: Date()).addingTimeInterval(Double(dayOffset) * 86_400)
    }

    private func row(_ r: SpotsViewModel.CompareRow) -> some View {
        HStack(spacing: DS.Spacing.m) {
            Text("\(r.maxScore)").font(DS.Font.score(28)).foregroundStyle(r.maxScore >= 70 ? DS.Color.accent : DS.Color.textPrimary).frame(width: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.spot.name).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                HStack(spacing: DS.Spacing.s) {
                    if let s = r.windowStart, let e = r.windowEnd {
                        Text("\(HomeViewModel.clock(s, timeZone: tz))〜\(HomeViewModel.clock(e, timeZone: tz))").font(DS.Font.number(12)).foregroundStyle(DS.Color.sun)
                    }
                    if let d = r.distanceM {
                        Text(d >= 1000 ? String(format: "%.0f km", d / 1000) : "\(Int(d)) m").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
            Spacer()
            Image(systemName: r.conditionCode.map { HomeViewModel.weatherSymbol($0) } ?? "minus").font(.system(size: 16)).foregroundStyle(DS.Color.textSecondary)
        }
        .padding(DS.Spacing.m)
        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
    }
}

/// 釣果情報のピン：魚のアイコンと件数。直近 7 日は濃く、2 週間を過ぎると薄く
struct FeedPinMarker: View {
    let pin: FeedCatchExtractor.Pin
    private var age: TimeInterval { Date().timeIntervalSince(pin.latestAt ?? .distantPast) }
    private var opacity: Double { age < 7 * 86_400 ? 1 : (age < 14 * 86_400 ? 0.75 : 0.45) }
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "fish.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.Color.background)
                Text(pin.speciesCounts.first.map { "\($0.0)" } ?? "記事").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Color.background).lineLimit(1)
                if pin.entries.count > 1 { Text("\(pin.entries.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(DS.Color.background.opacity(0.7)) }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(DS.Color.sun, in: Capsule())
            Triangle().fill(DS.Color.sun).frame(width: 8, height: 5)
        }
        .opacity(opacity)
    }

    struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
        }
    }
}

/// ピンをタップ：その場所の記事を新しい順に。魚種・日付・出典、タップで記事へ
struct FeedPinSheet: View {
    let pin: FeedCatchExtractor.Pin
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(pin.placeName).font(DS.Font.number(20)).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("\(pin.entries.count) 記事").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            if !pin.speciesCounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(Array(pin.speciesCounts.enumerated()), id: \.offset) { _, sc in
                            Text("\(sc.0) \(sc.1)").font(DS.Font.caption).foregroundStyle(DS.Color.background)
                                .padding(.horizontal, DS.Spacing.s).padding(.vertical, 3).background(DS.Color.sun, in: Capsule())
                        }
                    }
                }
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.s) {
                    ForEach(pin.entries) { e in
                        let content = VStack(alignment: .leading, spacing: 3) {
                            Text(e.title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(2)
                            HStack(spacing: DS.Spacing.s) {
                                if !e.species.isEmpty { Text(e.species.joined(separator: "・")).font(DS.Font.caption).foregroundStyle(DS.Color.sun) }
                                if let d = e.publishedAt { Text(d, format: .dateTime.month().day()).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary) }
                                Text(e.feedTitle).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                            }
                        }
                        .padding(DS.Spacing.m).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Color.panel, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                        if let link = e.link, let url = URL(string: link) { Link(destination: url) { content } } else { content }
                    }
                }
            }
            Text("見出しと要約に出た港名・釣り場名と魚種名から置いています。場所が書かれていない記事は出ません").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.background)
    }
}
