import Foundation
import CoreLocation
import MapKit
import Core

/// 「海岸線の近くか」と釣り場の名称候補。逆ジオコーディング（CLGeocoder）と MapKit の検索を使い、結果は 500 m メッシュでキャッシュする。
/// 圏外で判定できないときは nil（登録釣り場でなければ開始しない）。
@MainActor
final class ShoreOracle {
    struct Info: Codable {
        var nearShore: Bool
        var nameCandidate: String?
        var at: Date
    }

    private var cache: [String: Info] = [:]
    private let geocoder = CLGeocoder()
    static let keywords = ["港", "漁港", "埠頭", "岸壁", "防波堤", "海岸", "浜", "マリーナ", "桟橋", "堤防", "灯台", "海水浴場", "磯", "波止", "ふ頭", "河口"]

    private func key(_ c: Coordinate) -> String { String(format: "%.3f,%.3f", (c.latitude * 200).rounded() / 200, (c.longitude * 200).rounded() / 200) }

    func info(for coordinate: Coordinate) async -> Info? {
        let k = key(coordinate)
        if let cached = cache[k], Date().timeIntervalSince(cached.at) < 30 * 86_400 { return cached }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let texts = [placemark.name, placemark.thoroughfare, placemark.subLocality, placemark.locality].compactMap { $0 } + (placemark.areasOfInterest ?? [])
        var near = placemark.ocean != nil || placemark.inlandWater != nil
        var name: String? = placemark.areasOfInterest?.first ?? placemark.name
        if !near, texts.contains(where: { t in Self.keywords.contains { t.contains($0) } }) { near = true }
        if !near, let port = await nearestPort(around: coordinate) {
            near = true
            name = port
        }
        if name == nil { name = placemark.locality ?? placemark.subLocality }
        let info = Info(nearShore: near, nameCandidate: name, at: Date())
        cache[k] = info
        return info
    }

    /// 400 m 以内の漁港・港（MapKit の POI 検索、オンライン時のみ）。
    private func nearestPort(around c: Coordinate) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "漁港"
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), latitudinalMeters: 800, longitudinalMeters: 800)
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let near = response.mapItems.filter { item in
            let p = item.placemark.coordinate
            return Geo.distanceMeters(c, Coordinate(latitude: p.latitude, longitude: p.longitude)) <= 400
        }
        return near.first?.name
    }
}
