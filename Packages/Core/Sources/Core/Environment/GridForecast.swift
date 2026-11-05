import Foundation

/// 地図に重ねる格子の予報（F-43）。緯度 × 経度 × 時刻の値を変数ごとに持ち、位置と時刻で双一次補間する。
/// 気象（約 11 km）と海況（約 5 km）は格子が違うので別々の `GridForecast` にする。
public struct GridForecast: Codable, Hashable, Sendable {
    public enum Variable: String, Codable, CaseIterable, Sendable {
        case windSpeed, windDirection, windGust, airTemperature, precipitation, cloudCover, pressure
        case waveHeight, waveDirection, wavePeriod, swellHeight, swellDirection, currentSpeed, currentDirection, seaSurfaceTemperature
        /// 方向の変数か（補間は u/v で行う）
        public var isDirection: Bool { [.windDirection, .waveDirection, .swellDirection, .currentDirection].contains(self) }
    }

    /// 行 = 緯度（南→北）、列 = 経度（西→東）
    public var latitudes: [Double]
    public var longitudes: [Double]
    /// 時刻順（1 時間刻み）
    public var times: [Date]
    /// 変数 → 平坦な配列。index = t * rows * cols + r * cols + c。無い所は nil（陸など）
    public var values: [Variable: [Double?]]
    public var fetchedAt: Date

    public init(latitudes: [Double], longitudes: [Double], times: [Date], values: [Variable: [Double?]], fetchedAt: Date = .now) {
        self.latitudes = latitudes; self.longitudes = longitudes; self.times = times; self.values = values; self.fetchedAt = fetchedAt
    }

    public var rows: Int { latitudes.count }
    public var cols: Int { longitudes.count }
    public var isEmpty: Bool { times.isEmpty || rows == 0 || cols == 0 }

    public var latitudeRange: ClosedRange<Double>? { guard let a = latitudes.first, let b = latitudes.last else { return nil }; return a...b }
    public var longitudeRange: ClosedRange<Double>? { guard let a = longitudes.first, let b = longitudes.last else { return nil }; return a...b }

    public func value(_ v: Variable, timeIndex t: Int, row r: Int, col c: Int) -> Double? {
        guard let arr = values[v], t >= 0, r >= 0, c >= 0, t < times.count, r < rows, c < cols else { return nil }
        let i = t * rows * cols + r * cols + c
        return i < arr.count ? arr[i] : nil
    }

    /// 時刻の位置：直前の添字と、次の添字への割合（0〜1）。範囲外は端
    public func timePosition(_ date: Date) -> (index: Int, fraction: Double)? {
        guard let first = times.first, let last = times.last else { return nil }
        if date <= first { return (0, 0) }
        if date >= last { return (times.count - 1, 0) }
        let i = max(0, (times.lastIndex { $0 <= date } ?? 0))
        guard i + 1 < times.count else { return (i, 0) }
        let span = times[i + 1].timeIntervalSince(times[i])
        return (i, span > 0 ? date.timeIntervalSince(times[i]) / span : 0)
    }

    /// 格子の位置：行・列の添字と割合。範囲外は nil
    public func cell(for c: Coordinate) -> (row: Int, rowFraction: Double, col: Int, colFraction: Double)? {
        guard rows >= 2, cols >= 2, let lat = latitudeRange, let lon = longitudeRange, lat.contains(c.latitude), lon.contains(c.longitude) else { return nil }
        let r = (c.latitude - lat.lowerBound) / (lat.upperBound - lat.lowerBound) * Double(rows - 1)
        let cc = (c.longitude - lon.lowerBound) / (lon.upperBound - lon.lowerBound) * Double(cols - 1)
        let ri = min(rows - 2, Int(r.rounded(.down))), ci = min(cols - 2, Int(cc.rounded(.down)))
        return (ri, r - Double(ri), ci, cc - Double(ci))
    }

    /// スカラー値の双一次補間（空間）＋線形補間（時刻）。4 隅のうち nil は重みから外す。全部 nil なら nil
    public func sample(_ v: Variable, at c: Coordinate, time: Date) -> Double? {
        guard !v.isDirection else { return sampleDirection(v, at: c, time: time) }
        guard let cell = cell(for: c), let tp = timePosition(time) else { return nil }
        func spatial(_ t: Int) -> Double? {
            var sum = 0.0, w = 0.0
            for (dr, dc, wt) in [(0, 0, (1 - cell.rowFraction) * (1 - cell.colFraction)), (0, 1, (1 - cell.rowFraction) * cell.colFraction),
                                 (1, 0, cell.rowFraction * (1 - cell.colFraction)), (1, 1, cell.rowFraction * cell.colFraction)] {
                if let val = value(v, timeIndex: t, row: cell.row + dr, col: cell.col + dc) { sum += val * wt; w += wt }
            }
            return w > 0.001 ? sum / w : nil
        }
        let a = spatial(tp.index)
        guard tp.fraction > 0, tp.index + 1 < times.count, let b = spatial(tp.index + 1), let a else { return a }
        return a * (1 - tp.fraction) + b * tp.fraction
    }

    /// 方向（度）の補間：単位ベクトルで平均してから角度に戻す
    private func sampleDirection(_ v: Variable, at c: Coordinate, time: Date) -> Double? {
        guard let cell = cell(for: c), let tp = timePosition(time) else { return nil }
        var x = 0.0, y = 0.0, w = 0.0
        for (t, tw) in [(tp.index, 1 - tp.fraction), (tp.index + 1, tp.fraction)] where tw > 0 && t < times.count {
            for (dr, dc, wt) in [(0, 0, (1 - cell.rowFraction) * (1 - cell.colFraction)), (0, 1, (1 - cell.rowFraction) * cell.colFraction),
                                 (1, 0, cell.rowFraction * (1 - cell.colFraction)), (1, 1, cell.rowFraction * cell.colFraction)] {
                if let deg = value(v, timeIndex: t, row: cell.row + dr, col: cell.col + dc) {
                    let rad = deg * .pi / 180
                    x += cos(rad) * wt * tw; y += sin(rad) * wt * tw; w += wt * tw
                }
            }
        }
        guard w > 0.001 else { return nil }
        var deg = atan2(y, x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// 東向き u・北向き v の成分（速さの単位のまま）。`from` が true なら「吹いてくる向き」（風）、false なら「進む向き」（流れ・波）
    public func vector(speed: Variable, direction: Variable, at c: Coordinate, time: Date, from: Bool) -> (u: Double, v: Double)? {
        guard let s = sample(speed, at: c, time: time), let d = sample(direction, at: c, time: time) else { return nil }
        let rad = (from ? d + 180 : d) * .pi / 180
        // 気象の方位は北 0°・時計回り：u = s·sin θ、v = s·cos θ
        return (s * sin(rad), s * cos(rad))
    }

    /// 変数の値域（nil を除く）。凡例用
    public func range(of v: Variable) -> ClosedRange<Double>? {
        let vals = (values[v] ?? []).compactMap { $0 }
        guard let lo = vals.min(), let hi = vals.max() else { return nil }
        return lo...(hi > lo ? hi : lo + 1)
    }
}
