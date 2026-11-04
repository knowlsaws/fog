import Foundation
import Vision
import CoreImage
import Core

/// Vision の前景マスクで魚の輪郭を取り、主軸の両端と深度から全長を出す。
struct FishSegmenter {
    struct Result: Sendable {
        var measurement: LengthMeasurement?
        var status: FrameStatus
        var endpoints: (ImagePoint, ImagePoint)?
        var centroid: ImagePoint?
    }

    /// 画像内の最大の前景インスタンスを魚とみなす。
    func analyze(_ frame: DepthCaptureSession.Frame) -> Result {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.image, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
              let instance = observation.allInstances.first,
              let mask = try? observation.generateScaledMaskForImage(forInstances: [instance], from: handler) else {
            return Result(measurement: nil, status: .searching, endpoints: nil, centroid: nil)
        }
        let points = contourPoints(mask: mask, targetWidth: frame.imageSize.width, targetHeight: frame.imageSize.height)
        guard points.count >= 8, let (a, b) = LengthEstimator.principalAxisEndpoints(points) else {
            return Result(measurement: nil, status: .searching, endpoints: nil, centroid: nil)
        }
        let centroid = ImagePoint(x: points.reduce(0) { $0 + $1.x } / Double(points.count), y: points.reduce(0) { $0 + $1.y } / Double(points.count))
        // 両端の深度は輪郭のすぐ内側で取る（背景に落ちないように）
        let inset = 0.03
        let ia = ImagePoint(x: a.x + (b.x - a.x) * inset, y: a.y + (b.y - a.y) * inset)
        let ib = ImagePoint(x: b.x + (a.x - b.x) * inset, y: b.y + (a.y - b.y) * inset)
        let dc = DepthSampling.robustDepth(at: centroid, in: frame)
        guard let da = DepthSampling.robustDepth(at: ia, in: frame) ?? dc, let db = DepthSampling.robustDepth(at: ib, in: frame) ?? dc else {
            return Result(measurement: nil, status: LengthEstimator.frameStatus(distanceM: dc), endpoints: (a, b), centroid: centroid)
        }
        let m = LengthEstimator.measure(a: a, b: b, depthA: da, depthB: db, intrinsics: frame.intrinsics)
        return Result(measurement: m, status: LengthEstimator.frameStatus(distanceM: m?.distanceM ?? dc), endpoints: (a, b), centroid: centroid)
    }

    /// マスク（1 チャネル）の輪郭画素を間引いて画像座標で返す。
    func contourPoints(mask: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> [ImagePoint] {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let row = CVPixelBufferGetBytesPerRow(mask)
        let format = CVPixelBufferGetPixelFormatType(mask)
        let isFloat = format == kCVPixelFormatType_OneComponent32Float
        func on(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < w, y < h else { return false }
            if isFloat {
                return base.advanced(by: y * row + x * 4).assumingMemoryBound(to: Float32.self).pointee > 0.5
            }
            return base.advanced(by: y * row + x).assumingMemoryBound(to: UInt8.self).pointee > 127
        }
        var points: [ImagePoint] = []
        let step = max(1, min(w, h) / 160)
        let sx = Double(targetWidth) / Double(w), sy = Double(targetHeight) / Double(h)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if on(x, y) && (!on(x - step, y) || !on(x + step, y) || !on(x, y - step) || !on(x, y + step)) {
                    points.append(ImagePoint(x: Double(x) * sx, y: Double(y) * sy))
                }
                x += step
            }
            y += step
        }
        return points
    }
}
