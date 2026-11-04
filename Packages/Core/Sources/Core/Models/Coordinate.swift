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
}
