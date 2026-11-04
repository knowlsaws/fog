import Foundation
import XCTest
@testable import Core

/// L6 受け入れ条件: 修正した結果が次回の候補順に反映される。
final class SpeciesCorrectionTests: XCTestCase {
    func testCorrectionPromotesCorrectedSpecies() {
        var table = SpeciesCorrectionTable()
        let model = [SpeciesCandidate(species: "クジメ", confidence: 0.55), SpeciesCandidate(species: "アイナメ", confidence: 0.35), SpeciesCandidate(species: "ホッケ", confidence: 0.1)]
        XCTAssertEqual(table.rerank(model).first?.species, "クジメ")
        table.record(predicted: "クジメ", corrected: "アイナメ")
        table.record(predicted: "クジメ", corrected: "アイナメ")
        table.record(predicted: "クジメ", corrected: "アイナメ")
        let reranked = table.rerank(model)
        XCTAssertEqual(reranked.first?.species, "アイナメ", "\(reranked)")
        XCTAssertEqual(reranked.count, 3)
        XCTAssertEqual(table.correctionCount, 3)
        // 確信度の合計は保たれる（移動しただけ）
        XCTAssertEqual(reranked.reduce(0) { $0 + $1.confidence }, 1.0, accuracy: 0.1)
    }

    func testConfirmationBreaksTies() {
        var table = SpeciesCorrectionTable()
        let model = [SpeciesCandidate(species: "クロソイ", confidence: 0.4), SpeciesCandidate(species: "マゾイ", confidence: 0.4)]
        XCTAssertEqual(table.rerank(model).first?.species, "クロソイ") // 同点は名前順
        for _ in 0..<5 { table.record(predicted: "マゾイ", corrected: "マゾイ") }
        XCTAssertEqual(table.rerank(model).first?.species, "マゾイ")
    }

    func testRoundTripsThroughJSON() throws {
        var table = SpeciesCorrectionTable()
        table.record(predicted: "クジメ", corrected: "アイナメ")
        let data = try FogJSON.encode(table)
        XCTAssertEqual(try FogJSON.decode(SpeciesCorrectionTable.self, from: data), table)
    }

    func testEmptyCandidates() {
        XCTAssertTrue(SpeciesCorrectionTable().rerank([]).isEmpty)
    }
}
