import Foundation

/// 画像上の 2 点（魚の両端）と LiDAR 深度、カメラ内部パラメータから実寸を出す（F-11）。
/// 推定幅（±cm）は深度ノイズ・マスク解像度・奥行き差から見積もる。
public struct CameraIntrinsics: Hashable, Sendable {
    public var fx: Double, fy: Double, cx: Double, cy: Double
    public init(fx: Double, fy: Double, cx: Double, cy: Double) { self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy }
}

public struct ImagePoint: Hashable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct LengthMeasurement: Hashable, Sendable {
    public var lengthCm: Double
    public var errorCm: Double
    /// 魚までの距離（m）。計測枠の状態（遠い・近い）に使う
    public var distanceM: Double
    public init(lengthCm: Double, errorCm: Double, distanceM: Double) { self.lengthCm = lengthCm; self.errorCm = errorCm; self.distanceM = distanceM }
}

/// 計測枠の状態（撮影画面）。
public enum FrameStatus: String, Sendable {
    case searching   // 魚が見つからない
    case tooFar      // 遠い（下矢印）
    case tooClose    // 近い（上矢印）
    case ok          // 計測可能（オレンジ）
}

public enum LengthEstimator {
    /// 計測に適した距離（m）。LiDAR は 0.25〜5 m だが、魚の輪郭を取るには 0.3〜0.9 m。
    public static let minDistanceM = 0.3
    public static let maxDistanceM = 0.9

    public static func frameStatus(distanceM: Double?) -> FrameStatus {
        guard let d = distanceM, d > 0 else { return .searching }
        if d < minDistanceM { return .tooClose }
        if d > maxDistanceM { return .tooFar }
        return .ok
    }

    /// ピクセル座標を深度で 3 次元へ戻す（カメラ座標、m）。
    public static func unproject(_ p: ImagePoint, depthM: Double, intrinsics k: CameraIntrinsics) -> (x: Double, y: Double, z: Double) {
        ((p.x - k.cx) * depthM / k.fx, (p.y - k.cy) * depthM / k.fy, depthM)
    }

    /// 両端 `a`, `b` とその深度から全長を推定。`pixelError` はマスクの端の不確かさ（px）、深度ノイズは距離の 1%＋5 mm。
    public static func measure(a: ImagePoint, b: ImagePoint, depthA: Double, depthB: Double, intrinsics k: CameraIntrinsics,
                               pixelError: Double = 3) -> LengthMeasurement? {
        guard depthA > 0.05, depthB > 0.05, depthA < 10, depthB < 10 else { return nil }
        let pa = unproject(a, depthM: depthA, intrinsics: k)
        let pb = unproject(b, depthM: depthB, intrinsics: k)
        let dx = pa.x - pb.x, dy = pa.y - pb.y, dz = pa.z - pb.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let distance = (depthA + depthB) / 2
        // 誤差：端の画素誤差 × 1 画素あたりの実寸（両端）＋深度ノイズ × 奥行き差の寄与 ＋ 2%
        let perPixel = distance / min(k.fx, k.fy)
        let edge = 2 * pixelError * perPixel
        let depthNoise = 0.01 * distance + 0.005
        let depthTerm = abs(dz) > 0 ? depthNoise * (abs(dz) / max(length, 1e-6)) * 2 : depthNoise * 0.3
        let error = edge + depthTerm + 0.02 * length
        return LengthMeasurement(lengthCm: length * 100, errorCm: max(0.5, error * 100), distanceM: distance)
    }

    /// 楕円マスクの主軸両端（点群から最長の方向を求める）。輪郭点のピクセル座標を渡す。
    public static func principalAxisEndpoints(_ points: [ImagePoint]) -> (ImagePoint, ImagePoint)? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n, my = points.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = p.x - mx, dy = p.y - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        // 共分散の主固有ベクトル
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let ux = cos(theta), uy = sin(theta)
        var minT = Double.infinity, maxT = -Double.infinity
        var minP = points[0], maxP = points[0]
        for p in points {
            let t = (p.x - mx) * ux + (p.y - my) * uy
            if t < minT { minT = t; minP = p }
            if t > maxT { maxT = t; maxP = p }
        }
        return (minP, maxP)
    }
}
