import Foundation

/// 分析結果（釣れ率の重み、統計、図鑑の集約など）の置き場。
/// 値は常に保存データから導出し、ストアの `revision` が進んだら全部捨てる。削除が分析に即時反映される仕組みはこれだけに依存させる。
@MainActor
final class AnalysisCache {
    private var revision: Int = -1
    private var values: [String: Any] = [:]

    init() {}

    /// `store.revision` が変わっていなければキャッシュを返し、変わっていれば計算し直す。
    func value<T>(_ key: String, store: FogStore, compute: () throws -> T) rethrows -> T {
        if store.revision != revision {
            values.removeAll()
            revision = store.revision
        }
        if let cached = values[key] as? T { return cached }
        let fresh = try compute()
        values[key] = fresh
        return fresh
    }

    func invalidate() {
        values.removeAll()
        revision = -1
    }
}
