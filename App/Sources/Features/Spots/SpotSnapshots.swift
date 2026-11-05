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
    private var images: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    static let size = CGSize(width: 120, height: 76)

    private func key(_ c: Coordinate) -> String { String(format: "%.4f,%.4f", c.latitude, c.longitude) }

    func cached(for c: Coordinate) -> UIImage? { images[key(c)] }

    func image(for c: Coordinate) async -> UIImage? {
        guard c.isPlausible else { return nil }
        let k = key(c)
        if let img = images[k] { return img }
        if let t = inFlight[k] { return await t.value }
        let task = Task<UIImage?, Never> {
            let options = MKMapSnapshotter.Options()
            // 幅約 1 km・高さ約 630 m。北が上（回転なし）
            options.region = MKCoordinateRegion(center: c.cl, latitudinalMeters: 630, longitudinalMeters: 1000)
            options.size = Self.size
            options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
            options.pointOfInterestFilter = .excludingAll
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            do {
                let snap = try await MKMapSnapshotter(options: options).start()
                return snap.image
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

/// カードに置く航空写真：角丸、右上に「N」の印、取れるまでは暗い面
struct SpotSnapshotView: View {
    let coordinate: Coordinate
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                DS.Color.surface
            }
            HStack(spacing: 1) {
                Image(systemName: "arrow.up").font(.system(size: 7, weight: .bold))
                Text("N").font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(DS.Color.textPrimary)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(DS.Color.background.opacity(0.7), in: Capsule())
            .padding(4)
        }
        .frame(width: SpotSnapshots.size.width, height: SpotSnapshots.size.height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            image = SpotSnapshots.shared.cached(for: coordinate) ?? (await SpotSnapshots.shared.image(for: coordinate))
        }
    }
}
