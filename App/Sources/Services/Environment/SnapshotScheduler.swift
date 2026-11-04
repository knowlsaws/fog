import Foundation
import Core

/// 釣行中のスナップショット取得（30 分ごと＋釣果時）。環境 API は `EnvironmentService` が 1 時間間隔に抑える。
/// 釣行の開始・終了は L4 のセッション検出が呼ぶ。位置は呼び出し側が渡す（最後に分かっている立ち位置）。
@MainActor
@Observable
final class SnapshotScheduler {
    static let interval: TimeInterval = 30 * 60

    private let environment: EnvironmentService
    private let store: FogStore
    private var timer: Timer?
    private(set) var activeSessionID: UUID?
    private(set) var lastSnapshotAt: Date?
    var currentCoordinate: Coordinate?

    init(environment: EnvironmentService, store: FogStore) {
        self.environment = environment
        self.store = store
    }

    func start(session: Core.Session, coordinate: Coordinate) {
        activeSessionID = session.id
        currentCoordinate = coordinate
        environment.barometer.start()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.record(reason: .periodic) }
        }
        Task { await record(reason: .sessionStart) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        environment.barometer.stop()
        activeSessionID = nil
    }

    enum Reason { case sessionStart, periodic, catchEvent }

    /// スナップショットを 1 件追加して保存する。釣果時は `catchEvent` で呼ぶ（釣果側には別途 `environment.snapshot` を埋め込む）。
    @discardableResult
    func record(reason: Reason, at date: Date = .now) async -> EnvSnapshot? {
        guard let id = activeSessionID, let coordinate = currentCoordinate else { return nil }
        await environment.refreshIfNeeded(at: coordinate, now: date)
        guard var session = try? store.session(id: id) else { return nil }
        let snapshot = environment.snapshot(at: date, coordinate: coordinate)
        session.snapshots.append(snapshot)
        try? store.upsert(session)
        lastSnapshotAt = date
        return snapshot
    }
}
