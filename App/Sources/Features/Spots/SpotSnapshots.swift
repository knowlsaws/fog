import Foundation
import SwiftUI
import MapKit
import UIKit
import Core

/// 釣り場カードの小さな航空写真（F-46）。MapKit の静止画（衛星写真、北が上、約 1 km 幅）を釣り場ごとに 1 回だけ作って覚える。
/// 防波堤・岸壁の形が分かる。通信は Apple の地図（既に使っている）だけ
@MainActor
final class SpotSnapshots {
    static let shared = SpotSnapshots()
    private var images: [String: MKMapSnapshotter.Snapshot] = [:]
    private var inFlight: [String: Task<MKMapSnapshotter.Snapshot?, Never>] = [:]
    static let size = CGSize(width: 120, height: 76)

    private func key(_ c: Coordinate) -> String { String(format: "%.4f,%.4f", c.latitude, c.longitude) }

    func cached(for c: Coordinate) -> MKMapSnapshotter.Snapshot? { images[key(c)] }

    /// 写真と、座標を写真の中の位置に写す関数（点を重ねるため）
    func image(for c: Coordinate) async -> MKMapSnapshotter.Snapshot? {
        guard c.isPlausible else { return nil }
        let k = key(c)
        if let img = images[k] { return img }
        if let t = inFlight[k] { return await t.value }
        let task = Task<MKMapSnapshotter.Snapshot?, Never> {
            let options = MKMapSnapshotter.Options()
            // 幅約 1 km・高さ約 630 m。北が上（回転なし）
            options.region = MKCoordinateRegion(center: c.cl, latitudinalMeters: 630, longitudinalMeters: 1000)
            options.size = Self.size
            options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
            options.pointOfInterestFilter = .excludingAll
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            do {
                return try await MKMapSnapshotter(options: options).start()
            } catch {
                return nil
            }
        }
        inFlight[k] = task
        let img = await task.value
        inFlight[k] = nil
        if let img { images[k] = img }
        return img
    }
}

/// カードに置く航空写真：角丸、右上に「N」の印、取れるまでは暗い面。
/// 自分の釣果（テーマ色）・針ロスト（白）・釣果情報の記事（黄）の位置を点で重ねる（F-47）
struct SpotSnapshotView: View {
    let coordinate: Coordinate
    var catchPoints: [Coordinate] = []
    var lossPoints: [Coordinate] = []
    var feedPoints: [Coordinate] = []
    @State private var snapshot: MKMapSnapshotter.Snapshot?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let snapshot {
                Image(uiImage: snapshot.image).resizable().scaledToFill()
                ZStack(alignment: .topLeading) {
                    Color.clear
                    ForEach(Array(dots(snapshot).enumerated()), id: \.offset) { _, d in
                        Circle().fill(d.color).frame(width: d.size, height: d.size)
                            .overlay(Circle().stroke(DS.Color.background.opacity(0.8), lineWidth: 1))
                            .position(d.point)
                    }
                }
            } else {
                DS.Color.surface
            }
            // 地図アプリと同じ形の方位計（北が上）。赤い針が北
            CompassRose().frame(width: 18, height: 18).padding(4)
        }
        .frame(width: SpotSnapshots.size.width, height: SpotSnapshots.size.height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            if let c = SpotSnapshots.shared.cached(for: coordinate) {
                snapshot = c
            } else {
                snapshot = await SpotSnapshots.shared.image(for: coordinate)
            }
        }
    }

    private struct Dot { let point: CGPoint; let color: Color; let size: CGFloat }

    /// 写真の中に入る点だけ。記事の点は港の代表点そのものなら出さない（場所が「港」としか分からないため）
    private func dots(_ snap: MKMapSnapshotter.Snapshot) -> [Dot] {
        let size = SpotSnapshots.size
        func inside(_ p: CGPoint) -> Bool { p.x >= 2 && p.y >= 2 && p.x <= size.width - 2 && p.y <= size.height - 2 }
        var out: [Dot] = []
        for c in lossPoints { let p = snap.point(for: c.cl); if inside(p) { out.append(Dot(point: p, color: .white, size: 5)) } }
        for c in feedPoints where Geo.distanceMeters(c, coordinate) > 15 {
            let p = snap.point(for: c.cl); if inside(p) { out.append(Dot(point: p, color: DS.Color.sun, size: 6)) }
        }
        for c in catchPoints { let p = snap.point(for: c.cl); if inside(p) { out.append(Dot(point: p, color: DS.Color.accent, size: 6)) } }
        return out
    }
}

/// 小さな方位計：暗い円に、北を指す赤い針と南側の白い針。回転はしない（写真は常に北が上）
struct CompassRose: View {
    var body: some View {
        ZStack {
            Circle().fill(DS.Color.background.opacity(0.8))
            Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8)
            Needle().fill(Color(red: 0.95, green: 0.27, blue: 0.27)).padding(3)
            Needle().fill(Color.white.opacity(0.85)).rotationEffect(.degrees(180)).padding(3)
        }
    }

    /// 中心から上に伸びる細い三角（針の半分）
    struct Needle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: r.midX, y: r.midY)
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: c.x + r.width * 0.16, y: c.y))
            p.addLine(to: CGPoint(x: c.x - r.width * 0.16, y: c.y))
            p.closeSubpath()
            return p
        }
    }
}
