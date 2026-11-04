import Foundation
import Core
import os

/// 起動時に魚種カタログを揃える。L1〜L15 の確認用に入れていたダミー釣行（函館港・アイナメ）は L16 で外した。
/// すでにダミーが入っている端末では、起動時に 1 回だけそれを削除する（ID が固定なので実データとは混ざらない）。
enum CatalogSeeder {
    static let legacySeededKey = "fog.didSeedSampleSession"
    static let sampleRemovedKey = "fog.didRemoveSampleSession"
    private static let log = Logger(subsystem: "fog", category: "seed")

    @MainActor
    static func seedIfNeeded(store: FogStore) {
        do {
            try store.mergeSpecies(Species.initialCatalog)
        } catch {
            log.error("species catalog seed failed: \(error.localizedDescription, privacy: .public)")
        }
        removeLegacySampleIfNeeded(store: store)
    }

    @MainActor
    private static func removeLegacySampleIfNeeded(store: FogStore) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: sampleRemovedKey) else { return }
        defer { defaults.set(true, forKey: sampleRemovedKey) }
        guard defaults.bool(forKey: legacySeededKey) else { return }
        let sample = SampleData.session()
        guard let existing = try? store.session(id: sample.id), existing.startedAt == sample.startedAt else { return }
        try? store.deleteSession(id: sample.id)
        if let spot = try? store.spot(id: SampleData.spot().id), (try? store.sessions(spotID: spot.id))?.isEmpty ?? false {
            try? store.deleteSpot(id: spot.id)
        }
        try? store.deleteTackle(id: SampleData.tackle().id)
        try? store.deleteRig(id: SampleData.rig().id)
        log.info("legacy sample session removed")
    }
}
