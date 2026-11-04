import Foundation
import SwiftData
import Core

/// `Core.Point`（立ち位置メッシュ）の SwiftData 表現。
@Model
final class PointRecord {
    var uuid: UUID = UUID()
    var latitude: Double = 0
    var longitude: Double = 0
    var meshKey: String? = nil
    var createdAt: Date = Date()

    var spot: SpotRecord? = nil

    init(core: Point, spot: SpotRecord?) {
        uuid = core.id
        self.spot = spot
        apply(core)
    }

    func apply(_ core: Point) {
        latitude = core.coordinate.latitude
        longitude = core.coordinate.longitude
        meshKey = core.meshKey
        createdAt = core.createdAt
    }

    /// 釣り場が消えていれば nil。
    var core: Point? {
        guard let spotID = spot?.uuid else { return nil }
        return Point(id: uuid, spotID: spotID, coordinate: Coordinate(latitude: latitude, longitude: longitude), meshKey: meshKey, createdAt: createdAt)
    }
}
