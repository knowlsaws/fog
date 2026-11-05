import Foundation
import Core
import os

/// 地図レイヤー用の格子予報（F-43）。0.5° のタイル単位で取り、つなげて 1 枚の格子にする。
/// 表示範囲＋周り 1 周を先に取っておくので、パンしても端が出ない。タイルは 1 時間で取り直し、App Group に保存。
/// 気象は Forecast API（0.1° × 0.125°、6×5 点）、海況は Marine API（0.05° × 0.0625°、11×9 点）。地点は 50 ずつに分けて呼ぶ
@MainActor
@Observable
final class GridForecastService {
    struct Tile: Codable {
        var weather: GridForecast?
        var marine: GridForecast?
        var fetchedAt: Date
    }

    static let maxTilesPerRequest = 12
    static let maxCachedTiles = 40
    static let ttl: TimeInterval = 3600
    static let forecastDays = 3

    private(set) var tiles: [TileKey: Tile] = [:]
    /// タイルが増えた・更新されたら進む（ラスタの作り直しの合図）
    private(set) var version = 0
    private(set) var loading = false
    private(set) var lastError: String?
    private var inFlight: Set<TileKey> = []
    private var mosaicCache: (version: Int, marine: Bool, grid: GridForecast?)?
    private static let log = Logger(subsystem: "fog", category: "grid")
    private var url: URL { FogShared.containerURL.appendingPathComponent("grid-tiles.json") }

    init() { load() }

    /// 箱を覆うタイル＋周り 1 周を用意する。足りない・古いものだけ取る。近い順、同時 3 本まで
    func ensure(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, ring: Int = 1, now: Date = .now) {
        let center = Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        var keys = TileKey.covering(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, ring: ring)
        if keys.count > Self.maxTilesPerRequest {
            // 広すぎるときは周りを諦めて表示範囲だけ
            keys = TileKey.covering(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, ring: 0)
            if keys.count > Self.maxTilesPerRequest { keys = Array(TileKey.sortedByDistance(keys, from: center).prefix(Self.maxTilesPerRequest)) }
        }
        let needed = TileKey.sortedByDistance(keys, from: center).filter { k in
            !inFlight.contains(k) && ((tiles[k]?.fetchedAt ?? .distantPast) < now.addingTimeInterval(-Self.ttl))
        }
        guard !needed.isEmpty else { return }
        for k in needed { inFlight.insert(k) }
        loading = true
        Task { [weak self] in
            await withTaskGroup(of: (TileKey, GridForecast?, GridForecast?, String?).self) { group in
                var next = 0
                while next < min(3, needed.count) {
                    let k = needed[next]; next += 1
                    group.addTask { await Self.fetchTile(k, now: now) }
                }
                for await (k, w, m, err) in group {
                    guard let self else { return }
                    self.inFlight.remove(k)
                    if w != nil || m != nil {
                        self.tiles[k] = Tile(weather: w, marine: m, fetchedAt: now)
                        self.version += 1
                        self.lastError = nil
                    } else if let err {
                        self.lastError = err
                    }
                    if next < needed.count {
                        let k2 = needed[next]; next += 1
                        group.addTask { await Self.fetchTile(k2, now: now) }
                    }
                }
            }
            guard let self else { return }
            self.loading = !self.inFlight.isEmpty
            self.prune()
            self.save()
        }
    }

    /// 読み込んだタイルをつなげた格子（表示用）。版が変わるまで使い回す
    func mosaic(marine: Bool) -> GridForecast? {
        if let c = mosaicCache, c.version == version, c.marine == marine { return c.grid }
        let parts = tiles.values.compactMap { marine ? $0.marine : $0.weather }
        let grid = GridForecast.mosaic(parts, latStep: marine ? GridLattice.marineLatStep : GridLattice.weatherLatStep,
                                       lonStep: marine ? GridLattice.marineLonStep : GridLattice.weatherLonStep)
        mosaicCache = (version, marine, grid)
        return grid
    }

    /// 読み込み済みタイルの範囲
    var loadedBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard !tiles.isEmpty else { return nil }
        let keys = Array(tiles.keys)
        return (keys.map(\.minLat).min()!, keys.map(\.maxLat).max()!, keys.map(\.minLon).min()!, keys.map(\.maxLon).max()!)
    }

    func hasTile(for c: Coordinate) -> Bool { tiles[TileKey.containing(c)] != nil }

    nonisolated private static func fetchTile(_ key: TileKey, now: Date) async -> (TileKey, GridForecast?, GridForecast?, String?) {
        let w = GridLattice.points(for: key, marine: false)
        let m = GridLattice.points(for: key, marine: true)
        async let wr = download(OpenMeteoGrid.chunkedURLs(marine: false, latitudes: w.latitudes, longitudes: w.longitudes, forecastDays: forecastDays), lats: w.latitudes, lons: w.longitudes, now: now)
        async let mr = download(OpenMeteoGrid.chunkedURLs(marine: true, latitudes: m.latitudes, longitudes: m.longitudes, forecastDays: forecastDays), lats: m.latitudes, lons: m.longitudes, now: now)
        let (weather, marine) = await (wr, mr)
        var errors: [String] = []
        if case .failure(let e) = weather { errors.append("気象: \(e.localizedDescription)") }
        if case .failure(let e) = marine, (try? weather.get()) == nil { errors.append("海況: \(e.localizedDescription)") }
        if !errors.isEmpty { log.notice("tile \(key.latIndex),\(key.lonIndex): \(errors.joined(separator: " / "), privacy: .public)") }
        return (key, try? weather.get(), try? marine.get(), errors.isEmpty ? nil : errors.joined(separator: " / "))
    }

    nonisolated private static func download(_ urls: [URL], lats: [Double], lons: [Double], now: Date) async -> Result<GridForecast, Error> {
        do {
            var points: [OpenMeteoGrid.DecodedPoint] = []
            var lastError: Error?
            for url in urls {
                do {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 30
                    let (data, response) = try await URLSession.shared.data(for: req)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode), http.statusCode != 400 {
                        throw NSError(domain: "fog.grid", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                    }
                    points += try OpenMeteoGrid.decodePoints(data)
                } catch {
                    // 海況は全部陸の塊だとエラー応答になることがある。他の塊が取れていれば続ける
                    lastError = error
                }
            }
            if points.isEmpty, let lastError { throw lastError }
            return .success(try OpenMeteoGrid.assemble(points: points, latitudes: lats, longitudes: lons, fetchedAt: now))
        } catch {
            return .failure(error)
        }
    }

    /// 古い順に捨てて上限に収める
    private func prune() {
        guard tiles.count > Self.maxCachedTiles else { return }
        let sorted = tiles.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
        for (k, _) in sorted.prefix(tiles.count - Self.maxCachedTiles) { tiles[k] = nil }
        version += 1
    }

    private struct Persisted: Codable { var tiles: [String: Tile] }

    private func load() {
        guard let data = try? Data(contentsOf: url), let p = try? FogJSON.decode(Persisted.self, from: data) else { return }
        var out: [TileKey: Tile] = [:]
        for (k, t) in p.tiles {
            let parts = k.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            out[TileKey(latIndex: parts[0], lonIndex: parts[1])] = t
        }
        tiles = out
        version += 1
    }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: tiles.map { ("\($0.key.latIndex),\($0.key.lonIndex)", $0.value) })
        guard let data = try? FogJSON.encode(Persisted(tiles: dict), pretty: false) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
