#!/usr/bin/env swift
// Create ML で魚種分類モデルを学習する（macOS のみ）。
//   swift scripts/train_classifier/train.swift data/fish App/Resources/Models/FishClassifier.mlmodel docs/classifier_report.md
import Foundation
import CreateML

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: train.swift <data dir with train/ test/> <output .mlmodel> <report .md>")
    exit(2)
}
let dataDir = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let reportPath = URL(fileURLWithPath: args[3])
let trainDir = dataDir.appendingPathComponent("train")
let testDir = dataDir.appendingPathComponent("test")

var params = MLImageClassifier.ModelParameters()
params.maxIterations = 30
params.augmentation = [.flip, .crop, .exposure, .rotation]
params.validation = .split(strategy: .automatic)

do {
    let classifier = try MLImageClassifier(trainingData: .labeledDirectories(at: trainDir), parameters: params)
    let evaluation = classifier.evaluation(on: .labeledDirectories(at: testDir))
    let top1 = 1 - evaluation.classificationError
    // Top-3: 予測の確率分布から計算
    var top3Hits = 0, total = 0
    let fm = FileManager.default
    for species in (try? fm.contentsOfDirectory(atPath: testDir.path)) ?? [] where !species.hasPrefix(".") {
        let dir = testDir.appendingPathComponent(species)
        for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where file.lowercased().hasSuffix(".jpg") || file.lowercased().hasSuffix(".jpeg") || file.lowercased().hasSuffix(".png") {
            if let probs = try? classifier.predictions(from: .labeledDirectories(at: testDir)).count { _ = probs }
            total += 1
            if let dist = try? classifier.classifications(from: dir.appendingPathComponent(file)) {
                let top = dist.sorted { $0.value > $1.value }.prefix(3).map(\.key)
                if top.contains(species) { top3Hits += 1 }
            }
        }
    }
    let top3 = total > 0 ? Double(top3Hits) / Double(total) : 0
    let metadata = MLModelMetadata(author: "fog", shortDescription: "北海道の根魚を中心とした魚種分類", version: ISO8601DateFormatter().string(from: Date()))
    try classifier.write(to: output, metadata: metadata)
    let report = """
    # 魚種判定モデル

    - 学習日: \(ISO8601DateFormatter().string(from: Date()))
    - 学習データ: \(trainDir.path)
    - テスト: \(total) 枚
    - Top-1: \(String(format: "%.1f", top1 * 100))%
    - Top-3: \(String(format: "%.1f", top3 * 100))%
    - 受け入れ条件: Top-1 90% 以上・Top-3 98% 以上 → \(top1 >= 0.9 && top3 >= 0.98 ? "合格" : "不合格")
    """
    try report.write(to: reportPath, atomically: true, encoding: .utf8)
    print(report)
    exit(top1 >= 0.9 && top3 >= 0.98 ? 0 : 3)
} catch {
    print("training failed: \(error)")
    exit(1)
}
