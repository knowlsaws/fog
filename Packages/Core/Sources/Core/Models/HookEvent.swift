import Foundation

/// 針ロスト・針追加（例外的入力。ウィジェットの1タップ）。位置と時刻は自動で付き、根掛かりマップの元データになる（F-15）。
public struct HookEvent: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case lost
        case added
    }

    public var id: UUID
    public var sessionID: UUID
    public var pointID: UUID?
    public var at: Date
    public var coordinate: Coordinate
    public var kind: Kind
    public var rigID: UUID?

    public init(id: UUID = UUID(), sessionID: UUID, pointID: UUID? = nil, at: Date, coordinate: Coordinate, kind: Kind, rigID: UUID? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.pointID = pointID
        self.at = at
        self.coordinate = coordinate
        self.kind = kind
        self.rigID = rigID
    }
}
