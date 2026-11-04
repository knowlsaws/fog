import Foundation

/// 釣り場内の立ち位置（数十 m メッシュ）。釣果と針ロストを紐付け、ヒートマップ・根掛かりマップの単位になる（§3）。
public struct Point: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var spotID: UUID
    /// メッシュの中心。
    public var coordinate: Coordinate
    /// メッシュを一意にするキー（L4 で決める。例: "30m:4642:15637"）。未定なら nil。
    public var meshKey: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), spotID: UUID, coordinate: Coordinate, meshKey: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.spotID = spotID
        self.coordinate = coordinate
        self.meshKey = meshKey
        self.createdAt = createdAt
    }
}
