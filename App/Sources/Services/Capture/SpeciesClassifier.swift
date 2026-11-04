import Foundation
import CoreGraphics
import Core

/// 魚種判定（F-09）。L6 で Core ML 実装に置き換える。L5 では候補 3 種を低確信度で返す仮実装。
protocol SpeciesClassifying: Sendable {
    /// 候補（確信度順、最大 3 件）。空なら判定不能。
    func classify(_ image: CGImage) async -> [SpeciesCandidate]
}

struct PlaceholderSpeciesClassifier: SpeciesClassifying {
    func classify(_ image: CGImage) async -> [SpeciesCandidate] {
        // 主対象（高優先度）の先頭 3 種を低確信度で返す → 撮影画面は候補 3 種を出し、放置なら先頭で確定
        Species.initialCatalog.filter { $0.priority == .high }.prefix(3).enumerated().map { i, s in
            SpeciesCandidate(species: s.name, confidence: [0.4, 0.3, 0.2][i])
        }
    }
}
