import Foundation

/// 釣り場。自動検出で作られ（`isRegistered == false` の候補）、釣行が始まると登録済みになる。
public struct Spot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// 表示名。自動登録時は逆ジオコーディングの候補が入る（F-02）。
    public var name: String
    public var coordinate: Coordinate
    /// false は自動検出した未登録の漁港・岸壁（釣り場画面でグレーの点）。
    public var isRegistered: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, coordinate: Coordinate, isRegistered: Bool = true, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.isRegistered = isRegistered
        self.createdAt = createdAt
    }
}
