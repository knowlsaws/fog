import Foundation

// Core のモデルは純粋な値型（Codable, Hashable, Sendable）。
// SwiftData の @Model は App/Sources/Services/Persistence/ にあり、これらと相互変換する。

/// 緯度経度（WGS84、度）。
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 位置が取れないときの (0, 0) や範囲外ではない、使ってよい座標か。
    /// 位置なしで撮影した釣果が (0, 0) の釣り場を作り、ホームがギニア湾の天気を出す事故があった（2026-11-04）。
    public var isPlausible: Bool {
        guard abs(latitude) <= 90, abs(longitude) <= 180 else { return false }
        return !(abs(latitude) < 0.5 && abs(longitude) < 0.5)
    }
}
