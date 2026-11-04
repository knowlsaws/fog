import Foundation

/// 調和定数（分潮1つ分）。気象庁「分潮一覧表」の振幅(cm)・遅角(°)。
public struct TidalConstituent: Codable, Hashable, Sendable {
    public var name: String        // 例: "M2"
    public var amplitudeCm: Double
    public var phaseLagDeg: Double // κ（遅角、地方時基準）
    public init(name: String, amplitudeCm: Double, phaseLagDeg: Double) {
        self.name = name; self.amplitudeCm = amplitudeCm; self.phaseLagDeg = phaseLagDeg
    }
}

/// 潮位表掲載地点。`Packages/Core/Sources/Core/Data/harmonics.json` から読む。
public struct TideStation: Codable, Identifiable, Hashable, Sendable {
    public var id: String          // 地点記号（2桁）
    public var name: String
    public var coordinate: Coordinate
    /// Z0（潮位表基準面から平均水面までの高さ、cm）
    public var meanSeaLevelCm: Double
    public var constituents: [TidalConstituent]
    /// 遅角 κ の基準子午線（東経、度）。気象庁の分潮一覧表は「現地子午線基準」なので地点の経度。0 ならグリニッジ基準（G）。
    /// 現地の平衡潮引数は V_G + 種別 × 経度 になる（潮汐ポテンシャルの位相が m·(T_G + L) で決まるため）。
    public var lagLongitudeDeg: Double

    public init(id: String, name: String, coordinate: Coordinate, meanSeaLevelCm: Double, constituents: [TidalConstituent], lagLongitudeDeg: Double = 0) {
        self.id = id; self.name = name; self.coordinate = coordinate; self.meanSeaLevelCm = meanSeaLevelCm
        self.constituents = constituents; self.lagLongitudeDeg = lagLongitudeDeg
    }

    enum CodingKeys: String, CodingKey { case id, name, coordinate, meanSeaLevelCm, constituents, lagLongitudeDeg }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        coordinate = try c.decode(Coordinate.self, forKey: .coordinate)
        meanSeaLevelCm = try c.decode(Double.self, forKey: .meanSeaLevelCm)
        constituents = try c.decode([TidalConstituent].self, forKey: .constituents)
        lagLongitudeDeg = try c.decodeIfPresent(Double.self, forKey: .lagLongitudeDeg) ?? 0
    }
}

public struct TideExtreme: Hashable, Sendable {
    public enum Kind: String, Sendable { case high, low }
    public var kind: Kind
    public var at: Date
    public var levelCm: Double
    public init(kind: Kind, at: Date, levelCm: Double) { self.kind = kind; self.at = at; self.levelCm = levelCm }
}

/// 調和推算エンジン。η(t) = Z0 + Σ f_i H_i cos(V_i(t) + m_i·L + u_i − κ_i)
/// V はグリニッジ（UT）で評価し、κ の基準子午線 L（東経）と分潮の種別 m で現地の平衡潮引数に直す。
/// 函館・東京の気象庁潮位表との比較で RMS 1〜2 cm（検証: TideEngineTests）。
public struct TideEngine: Sendable {
    public var station: TideStation

    /// 初期化時に展開した分潮：係数ベクトル（T, s, h, p, N, p'）と位相、ノード因子の種類と重複度、振幅、遅角、m·L
    private struct Resolved {
        var coefficients: [Double]
        var phase: Double
        var nodal: [(ConstituentDefinition.Nodal, Int)]
        var amplitude: Double
        var lagRad: Double
        var speciesShiftDeg: Double
    }
    private let resolved: [Resolved]
    public let unknownConstituents: [String]

    public init(station: TideStation) {
        self.station = station
        var ok: [Resolved] = []
        var unknown: [String] = []
        for c in station.constituents {
            let name = ConstituentTable.canonicalName(c.name)
            guard let flat = ConstituentTable.flatten(name) else {
                unknown.append(c.name)
                continue
            }
            ok.append(Resolved(coefficients: flat.coefficients, phase: flat.phase, nodal: flat.nodal,
                               amplitude: c.amplitudeCm, lagRad: Angle.rad(c.phaseLagDeg),
                               speciesShiftDeg: flat.coefficients[0] * station.lagLongitudeDeg))
        }
        resolved = ok
        unknownConstituents = unknown
    }

    /// 指定時刻の推算潮位（cm、潮位表基準面上）。
    public func level(at date: Date) -> Double {
        let args = AstronomicalArguments(at: date)
        let vector = args.vector
        // ノード因子は種類ごとに 1 回だけ
        var nodalCache: [ConstituentDefinition.Nodal: (f: Double, u: Double)] = [:]
        func nodal(_ kind: ConstituentDefinition.Nodal) -> (f: Double, u: Double) {
            if let v = nodalCache[kind] { return v }
            let v = args.nodalFactors(kind)
            nodalCache[kind] = v
            return v
        }
        var sum = station.meanSeaLevelCm
        for c in resolved {
            var v = c.phase + c.speciesShiftDeg
            for i in 0..<6 { v += c.coefficients[i] * vector[i] }
            var f = 1.0, u = 0.0
            for (kind, k) in c.nodal {
                let n = nodal(kind)
                f *= pow(n.f, Double(abs(k)))
                u += n.u * Double(k)
            }
            sum += f * c.amplitude * cos(Angle.rad(v + u) - c.lagRad)
        }
        return sum
    }

    /// 潮位変化率（cm/時、正で上げ潮）。
    public func rate(at date: Date) -> Double {
        let dt: TimeInterval = 300
        return (level(at: date.addingTimeInterval(dt)) - level(at: date.addingTimeInterval(-dt))) / (2 * dt) * 3600
    }

    /// 期間内の満潮・干潮（時刻順）。10 分刻みで極値を挟み、黄金分割で詰める。
    public func extremes(from: Date, to: Date) -> [TideExtreme] {
        guard to > from else { return [] }
        var result: [TideExtreme] = []
        let step: TimeInterval = 600
        var t0 = from
        var l0 = level(at: t0)
        var t1 = t0.addingTimeInterval(step)
        var l1 = level(at: t1)
        while t1 < to.addingTimeInterval(step) {
            let t2 = t1.addingTimeInterval(step)
            let l2 = level(at: t2)
            if l1 > l0 && l1 >= l2 {
                let (t, l) = refine(t0, t2, maximizing: true)
                if t >= from && t <= to { result.append(TideExtreme(kind: .high, at: t, levelCm: l)) }
            } else if l1 < l0 && l1 <= l2 {
                let (t, l) = refine(t0, t2, maximizing: false)
                if t >= from && t <= to { result.append(TideExtreme(kind: .low, at: t, levelCm: l)) }
            }
            t0 = t1; l0 = l1; t1 = t2; l1 = l2
        }
        return result
    }

    /// `after` 以降の満干を `count` 個。
    public func nextExtremes(after date: Date, count: Int = 2) -> [TideExtreme] {
        var all: [TideExtreme] = []
        var from = date
        while all.count < count {
            let to = from.addingTimeInterval(2 * 86_400)
            all += extremes(from: from, to: to).filter { $0.at > date }
            from = to
            if from.timeIntervalSince(date) > 30 * 86_400 { break }
        }
        return Array(all.prefix(count))
    }

    private func refine(_ a: Date, _ b: Date, maximizing: Bool) -> (Date, Double) {
        var lo = a.timeIntervalSince1970, hi = b.timeIntervalSince1970
        let phi = (sqrt(5.0) - 1) / 2
        var x1 = hi - phi * (hi - lo), x2 = lo + phi * (hi - lo)
        var f1 = level(at: Date(timeIntervalSince1970: x1)), f2 = level(at: Date(timeIntervalSince1970: x2))
        for _ in 0..<40 {
            let better1 = maximizing ? f1 > f2 : f1 < f2
            if better1 {
                hi = x2; x2 = x1; f2 = f1
                x1 = hi - phi * (hi - lo); f1 = level(at: Date(timeIntervalSince1970: x1))
            } else {
                lo = x1; x1 = x2; f1 = f2
                x2 = lo + phi * (hi - lo); f2 = level(at: Date(timeIntervalSince1970: x2))
            }
            if hi - lo < 1 { break }
        }
        let t = Date(timeIntervalSince1970: (lo + hi) / 2)
        return (t, level(at: t))
    }
}
