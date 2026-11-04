import Foundation
import Core

/// アプリとウィジェット拡張で共有する置き場（App Group）。スナップショット・タックル選択・ウィジェットからの針ロスト。
/// このファイルは Fog と FogWidgets の両ターゲットでコンパイルされる。
enum FogShared {
    static let tackleKey = "fog.currentTackle"
    static let pendingHookLostKey = "fog.pendingHookLost"

    static var appGroupIdentifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "FogAppGroupIdentifier") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    /// App Group の UserDefaults。取れなければ standard（シミュレータ・未署名ビルド）。
    static let defaults: UserDefaults = {
        if let id = appGroupIdentifier, let d = UserDefaults(suiteName: id) { return d }
        return .standard
    }()

    static var containerURL: URL {
        let fm = FileManager.default
        var base: URL
        if let id = appGroupIdentifier, let url = fm.containerURL(forSecurityApplicationGroupIdentifier: id) {
            base = url
        } else {
            base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        }
        base.appendPathComponent("Fog", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var snapshotURL: URL { containerURL.appendingPathComponent("widget.json") }

    // MARK: スナップショット

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? WidgetSnapshot.from(json: data)
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let data = try? snapshot.jsonData() else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    /// 既存スナップショットの一部だけ更新する（記録中フラグ・タックル）。
    static func updateSnapshot(_ change: (inout WidgetSnapshot) -> Void) {
        guard var s = loadSnapshot() else { return }
        change(&s)
        saveSnapshot(s)
    }

    // MARK: タックル

    static var currentTackle: TackleKind? {
        get { TackleKind(rawValue: defaults.string(forKey: tackleKey) ?? "") }
        set { defaults.set(newValue?.rawValue, forKey: tackleKey) }
    }

    /// スピニング ⇄ ベイト。未選択ならスピニングから始めてベイトへ。
    @discardableResult
    static func toggleTackle() -> TackleKind {
        let next: TackleKind = (currentTackle ?? .spinning) == .spinning ? .bait : .spinning
        currentTackle = next
        updateSnapshot { $0.tackle = next }
        return next
    }

    // MARK: ウィジェットからの針ロスト（アプリが次に前面に来たとき取り込む）

    static func enqueueHookLost(at date: Date = .now) {
        var list = defaults.array(forKey: pendingHookLostKey) as? [Double] ?? []
        list.append(date.timeIntervalSince1970)
        defaults.set(list, forKey: pendingHookLostKey)
    }

    static func takePendingHookLost() -> [Date] {
        let list = defaults.array(forKey: pendingHookLostKey) as? [Double] ?? []
        defaults.removeObject(forKey: pendingHookLostKey)
        return list.map { Date(timeIntervalSince1970: $0) }
    }
}
