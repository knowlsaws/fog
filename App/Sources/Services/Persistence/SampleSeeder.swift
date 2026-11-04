import Foundation
import Core
import os

/// 初回起動でダミー釣行を1件入れる（L1 受け入れ条件「再起動後も残る」の確認用）。
/// 一度入れたら、後で消されても入れ直さない。魚種カタログは常に揃える。
enum SampleSeeder {
    static let seededKey = "fog.didSeedSampleSession"
    private static let log = Logger(subsystem: "fog", category: "seed")

    @MainActor
    static func seedIfNeeded(store: FogStore) {
        do {
            try store.mergeSpecies(Species.initialCatalog)
        } catch {
            log.error("species catalog seed failed: \(error.localizedDescription, privacy: .public)")
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        do {
            if try store.sessions().isEmpty {
                try store.upsert(SampleData.spot())
                try store.upsert(SampleData.point())
                try store.upsert(SampleData.tackle())
                try store.upsert(SampleData.rig())
                try store.upsert(SampleData.session())
                log.info("sample session seeded")
            }
            defaults.set(true, forKey: seededKey)
        } catch {
            log.error("sample seed failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
