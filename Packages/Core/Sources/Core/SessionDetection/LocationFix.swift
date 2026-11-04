import Foundation

/// 位置の 1 サンプル（CoreLocation の CLLocation を Core の値型にしたもの）。
public struct LocationFix: Codable, Hashable, Sendable {
    public var at: Date
    public var coordinate: Coordinate
    public var horizontalAccuracyM: Double
    /// m/s。不明なら nil
    public var speedMS: Double?

    public init(at: Date, coordinate: Coordinate, horizontalAccuracyM: Double = 20, speedMS: Double? = nil) {
        self.at = at; self.coordinate = coordinate; self.horizontalAccuracyM = horizontalAccuracyM; self.speedMS = speedMS
    }
}

/// 立ち位置のメッシュ（数十 m）。釣果・針ロストをポイント単位で集計する（§3）。
public enum Mesh {
    public static let defaultSizeM: Double = 30

    /// メッシュのキー（"30m:4642:15637" の形）。同じキーなら同じポイント。
    public static func key(for c: Coordinate, sizeM: Double = defaultSizeM) -> String {
        let (row, col) = indices(for: c, sizeM: sizeM)
        return "\(Int(sizeM))m:\(row):\(col)"
    }

    /// 経度の刻みは「行（緯度帯）の南端の緯度」で決める。点ごとの緯度で決めると同じ行でも境界が動くため。
    static func steps(row: Int, sizeM: Double) -> (lat: Double, lon: Double) {
        let latStep = sizeM / 111_320
        let rowLatitude = Double(row) * latStep
        let lonStep = sizeM / (111_320 * max(0.1, cos(Angle.rad(rowLatitude))))
        return (latStep, lonStep)
    }

    static func indices(for c: Coordinate, sizeM: Double) -> (Int, Int) {
        let latStep = sizeM / 111_320
        let row = Int((c.latitude / latStep).rounded(.down))
        let lonStep = steps(row: row, sizeM: sizeM).lon
        return (row, Int((c.longitude / lonStep).rounded(.down)))
    }

    /// メッシュの中心座標。
    public static func center(for c: Coordinate, sizeM: Double = defaultSizeM) -> Coordinate {
        let (row, col) = indices(for: c, sizeM: sizeM)
        let (latStep, lonStep) = steps(row: row, sizeM: sizeM)
        return Coordinate(latitude: (Double(row) + 0.5) * latStep, longitude: (Double(col) + 0.5) * lonStep)
    }
}
