import Foundation
import CoreGraphics
import Vision
import Core

/// 写真の背景を Vision の画像分類（端末内）で読み、足場・時間帯・天気のタグにする（F-31）。通信なし。
enum SceneClassifier {
    /// 失敗やタグ無しは nil。150 ms 程度
    static func tags(for image: CGImage) async -> [String]? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do { try handler.perform([request]) } catch { cont.resume(returning: nil); return }
                let labels: [(String, Double)] = (request.results ?? []).map { ($0.identifier, Double($0.confidence)) }
                let tags = SceneTagger.tags(from: labels)
                cont.resume(returning: tags.all.isEmpty ? nil : tags.all)
            }
        }
    }
}
