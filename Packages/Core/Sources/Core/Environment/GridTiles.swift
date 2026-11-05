import Foundation

/// 地図レイヤーの格子をタイル（0.5° × 0.5°）で持つ（F-43）。
/// 格子点は世界共通の格子（気象 0.1° × 0.125°、海況 0.05° × 0.0625°）に揃えるので、隣のタイルとつなげて 1 枚の格子にできる。
public struct TileKey: Hashable, Codable, Sendable {
    public var latIndex: Int
    public var lonIndex: Int
    public init(latIndex: Int, lonIndex: Int) { self.latIndex = latIndex; self.lonIndex = lonIndex }

    public static let sizeDeg = 0.5

    public var minLat: Double { Double(latIndex) * Self.sizeDeg }
    public var maxLat: Double { minLat + Self.sizeDeg }
    public var minLon: Double { Double(lonIndex) * Self.sizeDeg }
    public var maxLon: Double { minLon + Self.sizeDeg }
    public var center: Coordinate { Coordinate(latitude: minLat + Self.sizeDeg / 2, longitude: minLon + Self.sizeDeg / 2) }

    public static func containing(_ c: Coordinate) -> TileKey {
        TileKey(latIndex: Int((c.latitude / sizeDeg).rounded(.down)), lonIndex: Int((c.longitude / sizeDeg).rounded(.down)))
    }

    /// 箱を覆うタイル＋周り `ring` 周分。南西から北東へ行優先
    public static func covering(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, ring: Int = 0) -> [TileKey] {
        let a = containing(Coordinate(latitude: minLat, longitude: minLon)), b = containing(Coordinate(latitude: maxLat, longitude: maxLon))
        var out: [TileKey] = []
        for la in (a.latIndex - ring)...(b.latIndex + ring) { for lo in (a.lonIndex - ring)...(b.lonIndex + ring) { out.append(TileKey(latIndex: la, lonIndex: lo)) } }
        return out
    }

    /// 中心から近い順（先に見える所から取る）
    public static func sortedByDistance(_ keys: [TileKey], from c: Coordinate) -> [TileKey] {
        keys.sorted { Geo.distanceMeters($0.center, c) < Geo.distanceMeters($1.center, c) }
    }
}

public enum GridLattice {
    public static let weatherLatStep = 0.1, weatherLonStep = 0.125
    public static let marineLatStep = 0.05, marineLonStep = 0.0625

    /// タイルの格子点（端を含む。隣のタイルと端を共有する）
    public static func points(for tile: TileKey, marine: Bool) -> (latitudes: [Double], longitudes: [Double]) {
        let (ls, lo) = marine ? (marineLatStep, marineLonStep) : (weatherLatStep, weatherLonStep)
        let nLat = Int((TileKey.sizeDeg / ls).rounded()) + 1, nLon = Int((TileKey.sizeDeg / lo).rounded()) + 1
        func r(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }
        return ((0..<nLat).map { r(tile.minLat + Double($0) * ls) }, (0..<nLon).map { r(tile.minLon + Double($0) * lo) })
    }
}

public extension GridForecast {
    /// 同じ格子刻みのタイルをつなげて 1 枚にする。時刻は最新のタイルのものに揃え、同じ時刻の値だけ置く。
    /// 重なる端は後勝ち（どちらも同じ値のはず）。無い升は nil
    static func mosaic(_ tiles: [GridForecast], latStep: Double, lonStep: Double) -> GridForecast? {
        let usable = tiles.filter { !$0.isEmpty }
        guard let newest = usable.max(by: { $0.fetchedAt < $1.fetchedAt }) else { return nil }
        let minLat = usable.compactMap { $0.latitudes.first }.min()!, maxLat = usable.compactMap { $0.latitudes.last }.max()!
        let minLon = usable.compactMap { $0.longitudes.first }.min()!, maxLon = usable.compactMap { $0.longitudes.last }.max()!
        let rows = Int(((maxLat - minLat) / latStep).rounded()) + 1, cols = Int(((maxLon - minLon) / lonStep).rounded()) + 1
        func r4(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }
        let lats = (0..<rows).map { r4(minLat + Double($0) * latStep) }, lons = (0..<cols).map { r4(minLon + Double($0) * lonStep) }
        let times = newest.times
        let timeIndex = Dictionary(uniqueKeysWithValues: times.enumerated().map { ($0.element, $0.offset) })
        let tCount = times.count
        var values: [Variable: [Double?]] = [:]
        for tile in usable {
            // タイルの時刻 → 全体の時刻
            let tMap: [(Int, Int)] = tile.times.enumerated().compactMap { i, t in timeIndex[t].map { (i, $0) } }
            guard !tMap.isEmpty else { continue }
            let rowOf = tile.latitudes.map { Int((($0 - minLat) / latStep).rounded()) }
            let colOf = tile.longitudes.map { Int((($0 - minLon) / lonStep).rounded()) }
            for (v, arr) in tile.values {
                if values[v] == nil { values[v] = Array(repeating: nil, count: tCount * rows * cols) }
                for (ti, tg) in tMap {
                    for r in 0..<tile.rows {
                        let gr = rowOf[r]
                        guard gr >= 0, gr < rows else { continue }
                        for c in 0..<tile.cols {
                            let gc = colOf[c]
                            guard gc >= 0, gc < cols else { continue }
                            let src = ti * tile.rows * tile.cols + r * tile.cols + c
                            guard src < arr.count, let val = arr[src] else { continue }
                            values[v]![tg * rows * cols + gr * cols + gc] = val
                        }
                    }
                }
            }
        }
        return GridForecast(latitudes: lats, longitudes: lons, times: times, values: values, fetchedAt: newest.fetchedAt)
    }
}
