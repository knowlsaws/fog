import Foundation
import SwiftData
import Core

/// `Core.Spot` の SwiftData 表現。
/// CloudKit 同期のため、全属性に既定値を持たせ、リレーションは optional、`.unique` は使わない（全レコード共通）。
@Model
final class SpotRecord {
    var uuid: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var isRegistered: Bool = true
    var createdAt: Date = Date()

    /// 釣り場を消すと釣行も消える（§6 個別削除）。
    @Relationship(deleteRule: .cascade, inverse: \SessionRecord.spot)
    var sessions: [SessionRecord]? = nil

    @Relationship(deleteRule: .cascade, inverse: \PointRecord.spot)
    var points: [PointRecord]? = nil

    init(core: Spot) {
        uuid = core.id
        apply(core)
    }

    func apply(_ core: Spot) {
        name = core.name
        latitude = core.coordinate.latitude
        longitude = core.coordinate.longitude
        isRegistered = core.isRegistered
        createdAt = core.createdAt
    }

    var core: Spot {
        Spot(id: uuid, name: name, coordinate: Coordinate(latitude: latitude, longitude: longitude), isRegistered: isRegistered, createdAt: createdAt)
    }
}
