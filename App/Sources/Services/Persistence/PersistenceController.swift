import Foundation
import SwiftData
import os

/// SwiftData のストアを作る。起動は止めない：CloudKit → ローカルのみ → メモリ内 の順で落とす。
///
/// - 保存先は App Group のコンテナ（ウィジェットと共有。L14）。取れなければ Application Support。
/// - CloudKit 同期は、Info.plist の `FogCloudKitContainerIdentifier`（`project.yml` の `iCloud.${BUNDLE_ID_PREFIX}.fog`）があり、
///   端末が iCloud にサインインしていて、設定で無効化されていないときだけ有効。
///   開発者が Apple Developer でコンテナを作るまでは同期されないが、ローカル保存はそのまま動く（L1 受け入れ条件）。
final class PersistenceController {
    enum Mode: String {
        case cloudKit
        case local
        case inMemory
    }

    static let schema = Schema([
        SpotRecord.self,
        PointRecord.self,
        SessionRecord.self,
        CatchRecord.self,
        EnvSnapshotRecord.self,
        HookEventRecord.self,
        TackleRecord.self,
        RigRecord.self,
        SpeciesRecord.self,
    ])

    /// 設定画面（L15）でオフにできる。既定は有効。
    static let cloudSyncEnabledKey = "fog.cloudSyncEnabled"

    let container: ModelContainer
    let mode: Mode
    let storeURL: URL?
    let cloudKitContainerIdentifier: String?
    /// 望んだモードで開けなかったときの原因（設定画面の「iCloud 同期の状態」で見せる）。
    let fallbackError: Error?

    private static let log = Logger(subsystem: "fog", category: "persistence")

    private init(container: ModelContainer, mode: Mode, storeURL: URL?, cloudKitContainerIdentifier: String?, fallbackError: Error?) {
        self.container = container
        self.mode = mode
        self.storeURL = storeURL
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.fallbackError = fallbackError
    }

    // MARK: 生成

    static func live() -> PersistenceController {
        let url = storeURL()
        let cloudID = configuredCloudKitContainerIdentifier()
        var lastError: Error?

        if let cloudID, shouldAttemptCloudKit() {
            do {
                let config = ModelConfiguration("Fog", schema: schema, url: url, cloudKitDatabase: .private(cloudID))
                let container = try ModelContainer(for: schema, configurations: [config])
                log.info("store opened with CloudKit (\(cloudID, privacy: .public)) at \(url.path, privacy: .public)")
                return PersistenceController(container: container, mode: .cloudKit, storeURL: url, cloudKitContainerIdentifier: cloudID, fallbackError: nil)
            } catch {
                lastError = error
                log.error("CloudKit store failed, falling back to local: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            let config = ModelConfiguration("Fog", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            log.info("store opened locally at \(url.path, privacy: .public)")
            return PersistenceController(container: container, mode: .local, storeURL: url, cloudKitContainerIdentifier: cloudID, fallbackError: lastError)
        } catch {
            log.fault("local store failed, using in-memory: \(error.localizedDescription, privacy: .public)")
            let memory = inMemory(error: error)
            return memory
        }
    }

    /// プレビューとテスト用。
    static func inMemory(error: Error? = nil) -> PersistenceController {
        let config = ModelConfiguration("FogMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // メモリ内ストアの生成に失敗することは想定しない（失敗したらバグなので即座に分かるようにする）。
        let container = try! ModelContainer(for: schema, configurations: [config])
        return PersistenceController(container: container, mode: .inMemory, storeURL: nil, cloudKitContainerIdentifier: nil, fallbackError: error)
    }

    // MARK: 設定の読み取り

    static func configuredCloudKitContainerIdentifier() -> String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "FogCloudKitContainerIdentifier") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    static func configuredAppGroupIdentifier() -> String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "FogAppGroupIdentifier") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    static func shouldAttemptCloudKit() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: cloudSyncEnabledKey) != nil, !defaults.bool(forKey: cloudSyncEnabledKey) { return false }
        return FileManager.default.ubiquityIdentityToken != nil
    }

    /// App Group のコンテナ → Application Support。ディレクトリは作っておく。
    static func storeURL() -> URL {
        let fm = FileManager.default
        var base: URL
        if let group = configuredAppGroupIdentifier(), let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
            base = groupURL
        } else {
            base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
        }
        base.appendPathComponent("Fog", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Fog.store")
    }
}
