import Foundation
import SwiftUI
import Core

@MainActor
@Observable
final class SpotsViewModel {
    struct Card: Identifiable {
        let spot: Spot
        let stats: Analytics.SpotStats
        let score: Int
        let distanceM: Double?
        var id: UUID { spot.id }
    }

    private(set) var cards: [Card] = []
    private(set) var currentLocation: Coordinate?
    private var services: AppServices?
    private let cache = AnalysisCache()

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
