import Foundation
import Photos
import CoreImage
import CoreLocation
import UIKit
import Core

/// 写真の保存と取り込み（§6：写真はフォトライブラリを参照し、アプリにはサムネイルだけ持つ）。
struct PhotoLibraryService {
    static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// 撮影画像を JPEG でライブラリに保存し、localIdentifier を返す。
    func save(jpeg: Data, at date: Date, coordinate: Coordinate?) async throws -> String {
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpeg, options: nil)
            request.creationDate = date
            if let c = coordinate { request.location = CLLocation(latitude: c.latitude, longitude: c.longitude) }
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let identifier else { throw CocoaError(.fileWriteUnknown) }
        return identifier
    }

    /// 期間内（釣行中）に撮られた写真で、釣り場から 500 m 以内のもの（F-08）。
    func assets(from: Date, to: Date, near coordinate: Coordinate?, maxDistanceM: Double = 500) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@ AND mediaType = %d", from as NSDate, to as NSDate, PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var out: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if let coordinate, let loc = asset.location {
                let d = Geo.distanceMeters(coordinate, Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
                if d > maxDistanceM { return }
            }
            out.append(asset)
        }
        return out
    }

    /// 判定用の画像（長辺 1024）。
    func image(for asset: PHAsset, maxPixel: CGFloat = 1024) async -> CGImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: maxPixel, height: maxPixel), contentMode: .aspectFit, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image?.cgImage)
            }
        }
    }

    /// サムネイル JPEG（長辺 320）。
    /// 釣果の写真をフォトライブラリから削除する（iOS が確認ダイアログを出す）。
    static func delete(identifiers: [String]) async {
        let ids = Array(Set(identifiers)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    static func thumbnailJPEG(from cgImage: CGImage, maxPixel: CGFloat = 320) -> Data? {
        let image = UIImage(cgImage: cgImage)
        let scale = min(1, maxPixel / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.7)
    }
}

enum CaptureImageConverter {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// AR の撮影画像（横向き YCbCr）を縦向きの JPEG と CGImage に。
    static func jpegAndImage(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.9) -> (Data, CGImage)? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        guard let data = UIImage(cgImage: cg).jpegData(compressionQuality: quality) else { return nil }
        return (data, cg)
    }
}
