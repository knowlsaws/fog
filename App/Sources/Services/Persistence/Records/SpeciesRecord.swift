import Foundation
import SwiftData
import Core

/// `Core.Species` の SwiftData 表現。初期値は `Species.initialCatalog`、L6 で判定モデルに合わせて更新する。
@Model
final class SpeciesRecord {
    var key: String = ""
    var name: String = ""
    /// `[String]` の JSON。
    var aliasesData: Data? = nil
    var priorityRaw: String = Species.Priority.medium.rawValue

    init(core: Species) {
        key = core.id
        apply(core)
    }

    func apply(_ core: Species) {
        name = core.name
        aliasesData = core.aliases.isEmpty ? nil : BlobCodec.encode(core.aliases)
        priorityRaw = core.priority.rawValue
    }

    var core: Species {
        Species(
            id: key,
            name: name,
            aliases: BlobCodec.decode([String].self, from: aliasesData) ?? [],
            priority: Species.Priority(rawValue: priorityRaw) ?? .medium
        )
    }
}
