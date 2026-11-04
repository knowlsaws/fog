import Foundation

/// 連続撮影の同一個体まとめ（F-13）。数分以内の連続撮影で同じ魚種・近いサイズなら 1 尾にまとめ、ベストショットを自動選択する。
public enum CatchMerger {
    public static let window: TimeInterval = 3 * 60

    /// `existing` の中に `new` と同一個体とみなせるものがあればそれを返す。
    public static func findSameIndividual(for new: Catch, in existing: [Catch], window: TimeInterval = window) -> Catch? {
        existing
            .filter { abs($0.at.timeIntervalSince(new.at)) <= window }
            .filter { sameSpecies($0, new) && similarLength($0, new) }
            .max { $0.at < $1.at }
    }

    static func sameSpecies(_ a: Catch, _ b: Catch) -> Bool {
        if a.species.isEmpty || b.species.isEmpty { return true }
        if a.species == b.species { return true }
        // 低確信度どうしは候補が重なれば同じとみなす
        if a.speciesConfidence < 0.7 && b.speciesConfidence < 0.7 {
            let ca = Set(a.speciesCandidates.map(\.species)), cb = Set(b.speciesCandidates.map(\.species))
            return !ca.isDisjoint(with: cb)
        }
        return false
    }

    static func similarLength(_ a: Catch, _ b: Catch) -> Bool {
        guard let la = a.lengthCm, let lb = b.lengthCm else { return true } // 未計測は一致扱い
        let tolerance = max(3, 0.1 * max(la, lb)) + (a.lengthErrorCm ?? 0) + (b.lengthErrorCm ?? 0)
        return abs(la - lb) <= tolerance
    }

    /// `new` を `base` にまとめた結果。写真は全部残し、ベストショット（確信度が高く、推定幅の小さい方）を採用する。
    public static func merge(base: Catch, new: Catch) -> Catch {
        var m = base
        var photos = base.photoLocalIdentifiers
        if let p = base.photoLocalIdentifier, !photos.contains(p) { photos.append(p) }
        for p in [new.photoLocalIdentifier] + new.photoLocalIdentifiers {
            if let p, !photos.contains(p) { photos.append(p) }
        }
        m.photoLocalIdentifiers = photos
        // 魚種：確信度の高い方
        if new.speciesConfidence > base.speciesConfidence, !base.speciesCorrected {
            m.species = new.species
            m.speciesConfidence = new.speciesConfidence
            m.speciesCandidates = new.speciesCandidates
        }
        // サイズ：推定幅の小さい方（未計測なら計測済みを採用）
        switch (base.lengthCm, new.lengthCm) {
        case (nil, .some):
            m.lengthCm = new.lengthCm; m.lengthErrorCm = new.lengthErrorCm
            m.photoLocalIdentifier = new.photoLocalIdentifier ?? base.photoLocalIdentifier
        case (.some, .some):
            if (new.lengthErrorCm ?? .infinity) < (base.lengthErrorCm ?? .infinity) {
                m.lengthCm = new.lengthCm; m.lengthErrorCm = new.lengthErrorCm
                m.photoLocalIdentifier = new.photoLocalIdentifier ?? base.photoLocalIdentifier
            }
        default:
            break
        }
        if m.photoLocalIdentifier == nil { m.photoLocalIdentifier = new.photoLocalIdentifier }
        return m
    }
}
