import Foundation
import SwiftData
import Core

/// `Core.HookEvent`（針ロスト・追加）の SwiftData 表現。
@Model
final class HookEventRecord {
    var uuid: UUID = UUID()
    var pointID: UUID? = nil
    var at: Date = Date()
    var latitude: Double = 0
    var longitude: Double = 0
    var kindRaw: String = HookEvent.Kind.lost.rawValue
    var rigID: UUID? = nil

    var session: SessionRecord? = nil

    init(core: HookEvent, session: SessionRecord?) {
        uuid = core.id
        self.session = session
        apply(core)
    }

    func apply(_ core: HookEvent) {
        pointID = core.pointID
        at = core.at
        latitude = core.coordinate.latitude
        longitude = core.coordinate.longitude
        kindRaw = core.kind.rawValue
        rigID = core.rigID
    }

    func core(sessionID: UUID) -> HookEvent {
        HookEvent(
            id: uuid,
            sessionID: sessionID,
            pointID: pointID,
            at: at,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            kind: HookEvent.Kind(rawValue: kindRaw) ?? .lost,
            rigID: rigID
        )
    }
}
