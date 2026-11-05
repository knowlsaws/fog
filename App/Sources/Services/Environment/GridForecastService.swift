import Foundation
import Core
import os

/// 地図レイヤー用の格子予報（F-43）。釣り場画面で層を出したときだけ、表示中心の周り約 90 km 四方を
/// 気象（9×9、約 11 km）と海況（15×15、約 6 km）の 2 回の呼び出しで 3 日分取る。中心が 25 km 以上動くか 1 時間経ったら取り直す。
@MainActor
@Observable
final class GridForecastService {
    static let spanKm = 90.0
    static let weatherN = 9
    static let marineN = 15
    static let refetchDistanceM = 25_000.0

    private(set) var weather: GridForecast?
    private(set) var marine: GridForecast?
    private(set) var center: Coordinate?
    private(set) var loading = false
    private(set) var lastError: String?
    private var task: Task<Void, Never>?
    private static let log = Logger(subsystem: "fog", category: "grid")
    private var url: URL { FogShared.containerURL.appendingPathComponent("grid.json") }

    init() { load() }

    /// 表示中心に合わせて必要なら取り直す。取得中は重ねて呼ばない
    func ensure(center c: Coordinate, now: Date = .now) {
        guard c.isPlausible else { return }
        let fresh = (weather?.fetchedAt ?? .distantPast) > now.addingTimeInterval(-3600)
        if let center, fresh, Geo.distanceMeters(center, c) < Self.refetchDistanceM { return }
        guard task == nil else { return }
        loading = true
        task = Task { [weak self] in
            await self?.fetch(center: c, now: now)
            self?.loading = false
            self?.task = nil
        }
    }

    private func fetch(center c: Coordinate, now: Date) async {
        let w = OpenMeteoGrid.grid(center: c, spanKm: Self.spanKm, n: Self.weatherN)
        let m = OpenMeteoGrid.grid(center: c, spanKm: Self.spanKm, n: Self.marineN)
        // 地点数の上限と URL 長を避けて 50 地点ずつ。応答の座標は API が格子に寄せるので、最も近い升に置く
        async let weatherResult = Self.download(OpenMeteoGrid.chunkedURLs(marine: false, latitudes: w.latitudes, longitudes: w.longitudes), lats: w.latitudes, lons: w.longitudes, now: now)
        async let marineResult = Self.download(OpenMeteoGrid.chunkedURLs(marine: true, latitudes: m.latitudes, longitudes: m.longitudes), lats: m.latitudes, lons: m.longitudes, now: now)
        let (wr, mr) = await (weatherResult, marineResult)
        var errors: [String] = []
        switch wr { case .success(let g): weather = g; case .failure(let e): errors.append("気象: \(e.localizedDescription)") }
        switch mr { case .success(let g): marine = g; case .failure(let e): errors.append("海況: \(e.localizedDescription)") }
        if case .success = wr { center = c } else if case .success = mr { center = c }
        lastError = errors.isEmpty ? nil : errors.joined(separator: " / ")
        if !errors.isEmpty { Self.log.notice("grid fetch: \(errors.joined(separator: " / "), privacy: .public)") }
        save()
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

    private struct Persisted: Codable { var weather: GridForecast?; var marine: GridForecast?; var center: Coordinate? }

    private func load() {
        guard let data = try? Data(contentsOf: url), let p = try? FogJSON.decode(Persisted.self, from: data) else { return }
        weather = p.weather; marine = p.marine; center = p.center
    }

    private func save() {
        guard let data = try? FogJSON.encode(Persisted(weather: weather, marine: marine, center: center), pretty: false) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
