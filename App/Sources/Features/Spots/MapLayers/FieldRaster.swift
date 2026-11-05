import Foundation
import CoreGraphics
import MapKit
import Core

/// 地図の表示範囲（緯度経度の箱）に対して、色面の画像と粒子用の流れの格子を作る（F-43）。
/// 画像は箱の四隅を地図座標に写した長方形に描く。90 km 程度なら投影のずれは見えない
struct GeoBox: Equatable {
    var minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

    var widthMeters: Double { (maxLon - minLon) * 111_320 * cos((minLat + maxLat) / 2 * .pi / 180) }
    var heightMeters: Double { (maxLat - minLat) * 111_320 }

    /// 正規化座標（x: 西 0 → 東 1、y: 南 0 → 北 1）→ 緯度経度
    func coordinate(x: Double, y: Double) -> Coordinate {
        Coordinate(latitude: minLat + (maxLat - minLat) * y, longitude: minLon + (maxLon - minLon) * x)
    }

    /// 表示範囲が箱の中に収まっているか
    func contains(region: MKCoordinateRegion) -> Bool {
        let half = region.span.latitudeDelta / 2, halfLon = region.span.longitudeDelta / 2
        return region.center.latitude - half >= minLat && region.center.latitude + half <= maxLat
            && region.center.longitude - halfLon >= minLon && region.center.longitude + halfLon <= maxLon
    }

    /// 少し広げる（パンしても端が切れないように）
    func expanded(by f: Double) -> GeoBox {
        let dLat = (maxLat - minLat) * f, dLon = (maxLon - minLon) * f
        return GeoBox(minLat: minLat - dLat, maxLat: maxLat + dLat, minLon: minLon - dLon, maxLon: maxLon + dLon)
    }
}

struct FieldRaster: @unchecked Sendable {
    let box: GeoBox
    let layer: MapLayer
    let time: Date
    let image: CGImage?
    /// 粒子用：u（東向き）・v（北向き）の格子（行優先、南→北、西→東）。nil は値なし
    let uvCols: Int
    let uvRows: Int
    let u: [Float?]
    let v: [Float?]

    /// 正規化座標の流れ（m/s）。双一次補間。値なしは nil
    func velocity(x: Double, y: Double) -> (u: Double, v: Double)? {
        guard uvCols >= 2, uvRows >= 2, x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        let fx = x * Double(uvCols - 1), fy = y * Double(uvRows - 1)
        let c = min(uvCols - 2, Int(fx)), r = min(uvRows - 2, Int(fy))
        let tx = fx - Double(c), ty = fy - Double(r)
        var su = 0.0, sv = 0.0, w = 0.0
        for (dr, dc, wt) in [(0, 0, (1 - ty) * (1 - tx)), (0, 1, (1 - ty) * tx), (1, 0, ty * (1 - tx)), (1, 1, ty * tx)] {
            let i = (r + dr) * uvCols + (c + dc)
            if let uu = u[i], let vv = v[i] { su += Double(uu) * wt; sv += Double(vv) * wt; w += wt }
        }
        return w > 0.5 ? (su / w, sv / w) : nil
    }

    /// 色面と流れの格子を作る。`width`×`height` の画素、流れは `uvN` 刻み
    static func build(grid: GridForecast, layer: MapLayer, time: Date, box: GeoBox, opacity: Double = MapLayerSettings.defaultOpacity, width: Int = 180, height: Int = 240, uvN: Int = 36) -> FieldRaster {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let alpha = UInt8(max(0, min(255, opacity * 255)))
        for py in 0..<height {
            let y = 1 - (Double(py) + 0.5) / Double(height)
            for px in 0..<width {
                let x = (Double(px) + 0.5) / Double(width)
                guard let v = grid.sample(layer.scalar, at: box.coordinate(x: x, y: y), time: time) else { continue }
                let c = layer.rgb(v)
                let i = (py * width + px) * 4
                // premultipliedLast なので色にアルファを掛けておく
                let a = Int(alpha)
                pixels[i] = UInt8(Int(c.0) * a / 255); pixels[i + 1] = UInt8(Int(c.1) * a / 255); pixels[i + 2] = UInt8(Int(c.2) * a / 255); pixels[i + 3] = alpha
            }
        }
        var image: CGImage?
        pixels.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                image = ctx.makeImage()
            }
        }
        var u: [Float?] = [], vv: [Float?] = []
        if let vec = layer.vector {
            u.reserveCapacity(uvN * uvN); vv.reserveCapacity(uvN * uvN)
            for r in 0..<uvN {
                let y = Double(r) / Double(uvN - 1)
                for c in 0..<uvN {
                    let x = Double(c) / Double(uvN - 1)
                    if let w = grid.vector(speed: vec.speed, direction: vec.direction, at: box.coordinate(x: x, y: y), time: time, from: vec.from) {
                        u.append(Float(w.u)); vv.append(Float(w.v))
                    } else { u.append(nil); vv.append(nil) }
                }
            }
        }
        return FieldRaster(box: box, layer: layer, time: time, image: image, uvCols: u.isEmpty ? 0 : uvN, uvRows: u.isEmpty ? 0 : uvN, u: u, v: vv)
    }
}
