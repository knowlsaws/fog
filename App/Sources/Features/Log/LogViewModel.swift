import Foundation
import SwiftUI
import Core

/// ログ画面（§4）の状態。期間で絞った釣行と、その分析（時間帯別・潮別・釣り場別）を保存データから毎回導出する。
@MainActor
@Observable
final class LogViewModel {
    enum Period: String, CaseIterable, Identifiable {
        case month = "今月", season = "シーズン", all = "全期間"
        var id: String { rawValue }
    }

    struct SessionCard: Identifiable {
        let session: Core.Session
        let spotName: String
        let thumbnail: Data?
        var id: UUID { session.id }
    }

    var period: Period = .month { didSet { refresh() } }
    private(set) var cards: [SessionCard] = []
    private(set) var sessionCount = 0
    private(set) var catchCount = 0
    private(set) var latestReport: (summary: String, session: Core.Session)?
    private(set) var byHour: [(hour: Int, count: Int)] = []
    private(set) var byTide: [(label: String, count: Int)] = []
    private(set) var bySpot: [(name: String, perHour: Double, sessions: Int)] = []
    private(set) var allSessions: [Core.Session] = []
    private(set) var spots: [UUID: Spot] = [:]
    let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

    private var services: AppServices?

    func attach(_ services: AppServices) {
        self.services = services
        refresh()
    }

    func refresh() {
        guard let services else { return }
        let store = services.store
        allSessions = (try? store.sessions()) ?? []
        spots = Dictionary(uniqueKeysWithValues: ((try? store.spots()) ?? []).map { ($0.id, $0) })
        let filtered = allSessions.filter { !$0.isActive && inPeriod($0.startedAt) }
        cards = filtered.map { s in
            let best = s.catches.filter { $0.lengthCm != nil }.max { ($0.lengthCm ?? 0) < ($1.lengthCm ?? 0) } ?? s.catches.first
            return SessionCard(session: s, spotName: spots[s.spotID]?.name ?? "釣り場", thumbnail: best.flatMap { store.thumbnail(catchID: $0.id) })
        }
        sessionCount = filtered.count
        catchCount = filtered.reduce(0) { $0 + $1.catches.count }
        if let latest = allSessions.first(where: { $0.report != nil }), let r = latest.report {
            latestReport = (r.summary, latest)
        } else {
            latestReport = nil
        }
        let catches = filtered.flatMap(\.catches)
        let hours = Analytics.catchesByHour(catches: catches, timeZone: timeZone)
        byHour = (0..<24).map { (hour: $0, count: hours[$0] ?? 0) }
        let dist = Analytics.conditionDistribution(of: catches, timeZone: timeZone)
        var tide: [(String, Int)] = []
        for k in ["上げ", "下げ", "潮止まり"] { tide.append((k, dist.byTide[k] ?? 0)) }
        for k in ["大潮", "中潮", "小潮", "長潮", "若潮"] { tide.append((k, dist.byTideName[k] ?? 0)) }
        byTide = tide.map { (label: $0.0, count: $0.1) }
        bySpot = Analytics.statsBySpot(sessions: filtered).map { id, st in
            (name: spots[id]?.name ?? "釣り場", perHour: st.catchesPerHour, sessions: st.sessions)
        }.sorted { $0.perHour > $1.perHour }
    }

    private func inPeriod(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let now = Date()
        switch period {
        case .month:
            return cal.isDate(date, equalTo: now, toGranularity: .month)
        case .season:
            // シーズン＝直近 6 か月
            return date >= cal.date(byAdding: .month, value: -6, to: now)!
        case .all:
            return true
        }
    }

    /// 長押しで誤検出の釣行を削除（分析に即時反映）。
    func delete(_ session: Core.Session) {
        guard let services else { return }
        // 自動検出で釣果の無い釣行を消すのは誤検出の合図とみなし、その場所では自動で始めないようにする
        if session.isAutoDetected, session.catches.isEmpty {
            SessionDetectionService.exclude(session: session, spot: try? services.store.spot(id: session.spotID))
        }
        try? services.store.deleteSession(id: session.id)
        refresh()
    }

    func durationText(_ s: Core.Session) -> String {
        let minutes = Int((s.duration ?? 0) / 60)
        return minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 > 0 ? "\(minutes % 60)m" : "")" : "\(minutes)m"
    }
}
