import Foundation

/// ユーザーの修正による判定の補正（F-24）。端末内の補正テーブル。モデル自体はアプリ更新で配布する。
/// 「モデルが A と言ったが実際は B だった」回数を数え、次回から A の候補に B を繰り上げる。
public struct SpeciesCorrectionTable: Codable, Hashable, Sendable {
    /// predicted → (corrected → count)
    public var confusions: [String: [String: Int]]
    /// 魚種ごとの確定回数（候補順の同点を自分の実績で決める）
    public var confirmed: [String: Int]

    public init() { confusions = [:]; confirmed = [:] }

    public var correctionCount: Int { confusions.values.reduce(0) { $0 + $1.values.reduce(0, +) } }

    /// 修正を記録する。`predicted` が `corrected` と同じなら確定として数える。
    public mutating func record(predicted: String, corrected: String) {
        if predicted == corrected {
            confirmed[corrected, default: 0] += 1
            return
        }
        confusions[predicted, default: [:]][corrected, default: 0] += 1
        confirmed[corrected, default: 0] += 1
    }

    /// モデルの候補（確信度順）を補正して返す。
    /// - 誤判定の履歴：予測 A に対して B へ直した割合 r（平滑化）だけ A の確信度を B に移す
    /// - 確定実績：同点付近は自分がよく釣っている魚種を前に
    public func rerank(_ candidates: [SpeciesCandidate], maxCount: Int = 3) -> [SpeciesCandidate] {
        guard !candidates.isEmpty else { return [] }
        var scores: [String: Double] = [:]
        for c in candidates { scores[c.species, default: 0] += c.confidence }
        for c in candidates {
            guard let hist = confusions[c.species] else { continue }
            let total = Double(hist.values.reduce(0, +)) + 2   // 平滑化（2 回ぶんは「正しかった」とみなす）
            for (corrected, n) in hist {
                let r = Double(n) / total
                let moved = c.confidence * r
                scores[c.species, default: 0] -= moved
                scores[corrected, default: 0] += moved
            }
        }
        let maxConfirmed = Double(max(1, confirmed.values.max() ?? 1))
        let ranked = scores.map { species, score -> SpeciesCandidate in
            let bonus = 0.02 * Double(confirmed[species] ?? 0) / maxConfirmed
            return SpeciesCandidate(species: species, confidence: max(0, min(1, score + bonus)))
        }.sorted { $0.confidence > $1.confidence || ($0.confidence == $1.confidence && $0.species < $1.species) }
        return Array(ranked.prefix(maxCount))
    }
}
