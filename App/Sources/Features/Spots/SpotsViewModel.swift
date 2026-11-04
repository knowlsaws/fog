import Foundation
import SwiftUI
import MapKit
import Core

@MainActor
@Observable
final class SpotsViewModel {
    struct Card: Identifiable {
        let spot: Spot
        let stats: Analytics.SpotStats
        let score: Int
        let distanceM: Double?
        /// 地図検索で見つけた漁港（まだストアに無い）。「登録」で自分の釣り場になる
        var isCandidate: Bool = false
        var id: UUID { spot.id }
    }

    private(set) var cards: [Card] = []
    /// 表示中の地図範囲で見つけた漁港・港（未登録）。カードにも並べる
    private(set) var portCandidates: [Card] = []
    private(set) var currentLocation: Coordinate?
    private var services: AppServices?
    private let cache = AnalysisCache()
    private var candidateIDs: [String: UUID] = [:]
    private var lastSearchedRegion: MKCoordinateRegion?
    private var searchTask: Task<Void, Never>?

    /// 登録済み＋候補（近い順）
    var allCards: [Card] { (cards + portCandidates).sorted { ($0.distanceM ?? .infinity) < ($1.distanceM ?? .infinity) } }

    func attach(_ services: AppServices) {
        self.services = services
        refresh()
    }

    func refresh() {
        guard let services else { return }
        let store = services.store
        let spots = (try? store.spots()) ?? []
        let sessions = (try? store.sessions()) ?? []
        let bySpot = Analytics.statsBySpot(sessions: sessions)
        currentLocation = services.location.lastFix?.coordinate
        let now = Date()
        let personal = cache.value("personalModel", store: store) {
            PersonalModel.learn(from: sessions.filter { !$0.isActive }, coordinateOf: { s in spots.first { $0.id == s.spotID }?.coordinate })
        }
        let engine = ScoreEngine(personal: personal.total.hours >= 1 ? personal : nil)
        cards = spots.map { spot in
            let env = services.environment.snapshot(at: now, coordinate: spot.coordinate)
            let score = engine.score(ScoreInput(at: now, coordinate: spot.coordinate, env: env)).score
            let stats = bySpot[spot.id] ?? Analytics.spotStats(sessions: [])
            let d = currentLocation.map { Geo.distanceMeters($0, spot.coordinate) }
            return Card(spot: spot, stats: stats, score: score, distanceM: d)
        }.sorted { ($0.distanceM ?? .infinity) < ($1.distanceM ?? .infinity) }
    }

    // MARK: 漁港の自動表示（§7「自動検出した未登録の漁港・岸壁はグレーの点」）

    /// 地図の表示範囲が変わったら、その範囲の漁港・港を MapKit で探して候補にする。範囲が広すぎるときは探さない。
    func searchPorts(in region: MKCoordinateRegion) {
        guard region.span.latitudeDelta < 1.5 else { return }
        if let last = lastSearchedRegion {
            let moved = Geo.distanceMeters(Coordinate(latitude: last.center.latitude, longitude: last.center.longitude),
                                           Coordinate(latitude: region.center.latitude, longitude: region.center.longitude))
            let spanRatio = region.span.latitudeDelta / max(0.0001, last.span.latitudeDelta)
            if moved < region.span.latitudeDelta * 111_000 * 0.2, spanRatio > 0.6, spanRatio < 1.6 { return }
        }
        lastSearchedRegion = region
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            var found: [MKMapItem] = []
            for query in ["漁港", "港"] {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = region
                request.resultTypes = .pointOfInterest
                if let items = try? await MKLocalSearch(request: request).start().mapItems { found += items }
                if Task.isCancelled { return }
            }
            await MainActor.run { self?.setPortCandidates(found) }
        }
    }

    private func setPortCandidates(_ items: [MKMapItem]) {
        guard let services else { return }
        let existing = (try? services.store.spots()) ?? []
        let sessions = (try? services.store.sessions()) ?? []
        let spots = existing
        let personal = cache.value("personalModel", store: services.store) {
            PersonalModel.learn(from: sessions.filter { !$0.isActive }, coordinateOf: { s in spots.first { $0.id == s.spotID }?.coordinate })
        }
        let engine = ScoreEngine(personal: personal.total.hours >= 1 ? personal : nil)
        let now = Date()
        var out: [Card] = []
        for item in items {
            guard let name = item.name, name.contains("港") || name.contains("岸壁") || name.contains("埠頭") || name.contains("防波堤") else { continue }
            let c = Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            if existing.contains(where: { Geo.distanceMeters($0.coordinate, c) < 300 }) { continue }
            if out.contains(where: { Geo.distanceMeters($0.spot.coordinate, c) < 300 }) { continue }
            let key = "\(name)@\(Int(c.latitude * 1000)),\(Int(c.longitude * 1000))"
            let id = candidateIDs[key] ?? UUID()
            candidateIDs[key] = id
            let env = services.environment.snapshot(at: now, coordinate: c)
            let score = engine.score(ScoreInput(at: now, coordinate: c, env: env)).score
            let spot = Spot(id: id, name: name, coordinate: c, isRegistered: false)
            out.append(Card(spot: spot, stats: Analytics.spotStats(sessions: []), score: score,
                            distanceM: currentLocation.map { Geo.distanceMeters($0, c) }, isCandidate: true))
        }
        portCandidates = out
    }

    /// 候補の漁港を自分の釣り場として登録する（よく行く漁港）。
    func register(_ card: Card) {
        guard let services else { return }
        var spot = card.spot
        spot.isRegistered = true
        spot.createdAt = .now
        try? services.store.upsert(spot)
        portCandidates.removeAll { $0.id == card.id }
        refresh()
    }

    /// 検索結果から未登録の候補を置く（釣行が始まれば登録済みになる）。
    func addCandidate(name: String, coordinate: Coordinate) {
        guard let services else { return }
        let existing = (try? services.store.spots()) ?? []
        if existing.contains(where: { Geo.distanceMeters($0.coordinate, coordinate) < 300 }) { refresh(); return }
        try? services.store.upsert(Spot(name: name, coordinate: coordinate, isRegistered: false))
        refresh()
    }

    func selectForHome(_ spot: Spot) {
        UserDefaults.standard.set(spot.id.uuidString, forKey: "fog.homeSpotID")
    }

    func rename(_ spot: Spot, to name: String) {
        guard let services else { return }
        var s = spot
        s.name = name
        try? services.store.upsert(s)
        refresh()
    }

    func delete(_ spot: Spot) {
        guard let services else { return }
        try? services.store.deleteSpot(id: spot.id)
        refresh()
    }
}
