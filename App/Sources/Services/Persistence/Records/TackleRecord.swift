import Foundation
import SwiftData
import Core

/// `Core.Tackle` の SwiftData 表現。
@Model
final class TackleRecord {
    var uuid: UUID = UUID()
    var kindRaw: String = TackleKind.spinning.rawValue
    var name: String = ""
    var rod: String = ""
    var reel: String = ""
    var line: String = ""
    var createdAt: Date = Date()

    init(core: Tackle) {
        uuid = core.id
        apply(core)
    }

    func apply(_ core: Tackle) {
        kindRaw = core.kind.rawValue
        name = core.name
        rod = core.rod
        reel = core.reel
        line = core.line
        createdAt = core.createdAt
    }

    var core: Tackle {
        Tackle(id: uuid, kind: TackleKind(rawValue: kindRaw) ?? .spinning, name: name, rod: rod, reel: reel, line: line, createdAt: createdAt)
    }
}

/// `Core.Rig` の SwiftData 表現。
@Model
final class RigRecord {
    var uuid: UUID = UUID()
    var name: String = ""
    var sinkerGrams: Double = 0
    var hookSize: String = ""
    var worm: String = ""
    var sortOrder: Int = 0

    init(core: Rig) {
        uuid = core.id
        apply(core)
    }

    func apply(_ core: Rig) {
        name = core.name
        sinkerGrams = core.sinkerGrams
        hookSize = core.hookSize
        worm = core.worm
        sortOrder = core.sortOrder
    }

    var core: Rig {
        Rig(id: uuid, name: name, sinkerGrams: sinkerGrams, hookSize: hookSize, worm: worm, sortOrder: sortOrder)
    }
}
