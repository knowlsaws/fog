import Foundation
import SwiftData
import Core

/// `Core.Note`（地図のメモ）の SwiftData 表現。CloudKit 同期のため全属性に既定値、`.unique` は使わない。
@Model
final class NoteRecord {
    var uuid: UUID = UUID()
    var latitude: Double = 0
    var longitude: Double = 0
    var text: String = ""
    var placeName: String? = nil
    var source: String = "manual"
    var createdAt: Date = Date()

    init(core: Core.Note) {
        uuid = core.id
        apply(core)
    }

    func apply(_ core: Core.Note) {
        latitude = core.coordinate.latitude
        longitude = core.coordinate.longitude
        text = core.text
        placeName = core.placeName
        source = core.source.rawValue
        createdAt = core.createdAt
    }

    var core: Core.Note {
        Core.Note(id: uuid, coordinate: Coordinate(latitude: latitude, longitude: longitude), text: text, placeName: placeName,
                  source: Core.Note.Source(rawValue: source) ?? .manual, createdAt: createdAt)
    }
}
