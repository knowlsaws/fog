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

/// 潮位表掲載地点。L2 で data/tide/harmonics.json から読み込む。
public struct TideStation: Codable, Identifiable, Hashable, Sendable {
    public var id: String          // 地点記号（2桁）
    public var name: String
    public var coordinate: Coordinate
    public var meanSeaLevelCm: Double   // Z0（潮位表基準面からの平均水面）
    public var constituents: [TidalConstituent]
    public init(id: String, name: String, coordinate: Coordinate, meanSeaLevelCm: Double, constituents: [TidalConstituent]) {
        self.id = id; self.name = name; self.coordinate = coordinate; self.meanSeaLevelCm = meanSeaLevelCm; self.constituents = constituents
    }
}

public struct TideExtreme: Hashable, Sendable {
    public enum Kind: Sendable { case high, low }
    public var kind: Kind
    public var at: Date
    public var levelCm: Double
}

/// 調和推算エンジン。H(t) = Z0 + Σ f_i H_i cos(ω_i t + V0_i + u_i − κ_i)
/// L0 では骨組みのみ。分潮の角速度・天文引数・ノード因子のテーブルは L2 で実装する。
public struct TideEngine: Sendable {
    public var station: TideStation
    public init(station: TideStation) { self.station = station }

    /// 指定時刻の推算潮位(cm)。L2 で実装。
    public func level(at date: Date) -> Double {
        // TODO(L2): 分潮テーブル（角速度 ω、天文引数 V0、ノード因子 f, u）を用いた推算
        return station.meanSeaLevelCm
    }

    /// 期間内の満潮・干潮。L2 で実装（level の極値探索）。
    public func extremes(from: Date, to: Date) -> [TideExtreme] { [] }
}
