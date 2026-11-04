import Foundation
import CoreLocation
import Core
import os

/// 釣行の自動開始・終了（F-01）、釣り場の自動登録（F-02）、立ち位置のポイント化（§3）。
/// 位置は `LocationService`、判定は Core の `SessionDetector`、保存は `FogStore`、環境は `SnapshotScheduler`。
@MainActor
@Observable
final class SessionDetectionService {
    static let sensitivityKey = "fog.detectionSensitivity"
    static let registeredSpotRadiusM: Double = 300

    private(set) var detector: SessionDetector
    private(set) var activeSessionID: UUID?
    private(set) var activeSpotName: String?
    private var lastEndedSessionID: UUID?

    private let location: LocationService
    private let store: FogStore
    private let scheduler: SnapshotScheduler
    private let environment: EnvironmentService
    private let shore = ShoreOracle()
    private var task: Task<Void, Never>?
    /// 終了直後に呼ばれる（写真の取り込み・レポート生成など）。保存済みの釣行 ID を渡す
    var onSessionEnded: ((UUID) -> Void)?
    private static let log = Logger(subsystem: "fog", category: "session")

    init(location: LocationService, store: FogStore, scheduler: SnapshotScheduler, environment: EnvironmentService) {
        self.location = location
        self.store = store
        self.scheduler = scheduler
        self.environment = environment
        detector = SessionDetector(settings: .forSensitivity(Self.sensitivity))
    }

    static var sensitivity: DetectionSettings.Sensitivity {
        get { DetectionSettings.Sensitivity(rawValue: UserDefaults.standard.string(forKey: sensitivityKey) ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sensitivityKey) }
    }

    func applySensitivity(_ s: DetectionSettings.Sensitivity) {
        Self.sensitivity = s
        detector.settings = .forSensitivity(s)
    }

    // MARK: 起動

    func start() {
        SessionNotifications.registerCategories()
        location.requestAuthorization()
        // 記録中の釣行が残っていれば引き継ぐ（アプリ再起動後）
        if let active = try? store.activeSession() {
            resumeTracking(session: active)
        } else {
            location.startMonitoring()
        }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            for await fix in location.fixes() {
                await self.handle(fix)
            }
        }
    }

    private func resumeTracking(session: Core.Session) {
        activeSessionID = session.id
        activeSpotName = (try? store.spot(id: session.spotID))?.name
        location.startTracking()
        if let coordinate = session.track.last?.coordinate ?? (try? store.spot(id: session.spotID))?.coordinate {
            scheduler.start(session: session, coordinate: coordinate)
        }
    }

    // MARK: 位置の処理

    func handle(_ fix: LocationFix) async {
        let context = await context(for: fix)
        let events = detector.handle(fix, context: context)
        for event in events {
            switch event {
            case .start(let at, let anchor, let spotID):
                await startSession(at: at, anchor: anchor, spotID: spotID)
            case .resume(_, let at, let anchor):
                await resumeSession(at: at, anchor: anchor)
            case .end(let at):
                await endSession(at: at)
            case .track(let sample):
                recordTrack(sample)
            }
        }
        if activeSessionID != nil { scheduler.currentCoordinate = fix.coordinate }
    }

    private func context(for fix: LocationFix) async -> SessionDetector.Context {
        let spots = (try? store.spots()) ?? []
        let registered = spots.filter(\.isRegistered)
            .min { Geo.distanceMeters($0.coordinate, fix.coordinate) < Geo.distanceMeters($1.coordinate, fix.coordinate) }
        if let registered, Geo.distanceMeters(registered.coordinate, fix.coordinate) <= Self.registeredSpotRadiusM {
            return .init(registeredSpotID: registered.id, nearShore: true)
        }
        // 走行中は逆ジオコーディングしない（無駄な通信を避ける）
        if (fix.speedMS ?? 0) >= detector.settings.drivingSpeedMS { return .init(registeredSpotID: nil, nearShore: nil) }
        let info = await shore.info(for: fix.coordinate)
        return .init(registeredSpotID: nil, nearShore: info?.nearShore)
    }

    // MARK: 開始・再開・終了

    private func startSession(at: Date, anchor: Coordinate, spotID: UUID?) async {
        var spot: Spot
        if let spotID, let existing = try? store.spot(id: spotID) {
            spot = existing
        } else {
            let info = await shore.info(for: anchor)
            spot = Spot(name: info?.nameCandidate ?? "釣り場", coordinate: anchor, isRegistered: true, createdAt: at)
            try? store.upsert(spot)
        }
        // 前回のタックル・リグを引き継ぐ（F-14）
        let previous = (try? store.sessions())?.first
        let session = Core.Session(spotID: spot.id, startedAt: at, tackle: previous?.tackle, rigID: previous?.rigID,
                                   track: [TrackSample(at: at, coordinate: anchor)], tackleID: previous?.tackleID, isAutoDetected: true)
        do {
            try store.upsert(session)
        } catch {
            Self.log.error("session start save failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        activeSessionID = session.id
        activeSpotName = spot.name
        location.startTracking()
        scheduler.start(session: session, coordinate: anchor)
        SessionNotifications.sessionStarted(spotName: spot.name, sessionID: session.id)
        Self.log.info("session started at \(spot.name, privacy: .public)")
    }

    private func resumeSession(at: Date, anchor: Coordinate) async {
        guard let id = lastEndedSessionID, var session = try? store.session(id: id) else {
            await startSession(at: at, anchor: anchor, spotID: nil)
            return
        }
        session.endedAt = nil
        session.track.append(TrackSample(at: at, coordinate: anchor))
        try? store.upsert(session)
        activeSessionID = session.id
        location.startTracking()
        scheduler.start(session: session, coordinate: anchor)
        Self.log.info("session resumed (run and gun)")
    }

    func endSession(at: Date) async {
        guard let id = activeSessionID, var session = try? store.session(id: id) else { return }
        session.endedAt = at
        session.activity = await PedometerService().activity(from: session.startedAt, to: at)
        session = await environment.backfill(session)
        try? store.upsert(session)
        onSessionEnded?(id)
        scheduler.stop()
        location.startMonitoring()
        lastEndedSessionID = id
        activeSessionID = nil
        let spotName = (try? store.spot(id: session.spotID))?.name ?? "釣り場"
        SessionNotifications.sessionEnded(spotName: spotName, catches: session.catches.count, summary: session.report?.summary, sessionID: id)
        Self.log.info("session ended with \(session.catches.count) catches")
    }

    private func recordTrack(_ sample: TrackSample) {
        guard let id = activeSessionID, var session = try? store.session(id: id) else { return }
        session.track.append(sample)
        try? store.upsert(session)
        // メッシュのポイントを用意しておく（釣果・針ロストが紐付く単位）
        let key = Mesh.key(for: sample.coordinate)
        if let points = try? store.points(spotID: session.spotID), !points.contains(where: { $0.meshKey == key }) {
            try? store.upsert(Point(spotID: session.spotID, coordinate: Mesh.center(for: sample.coordinate), meshKey: key, createdAt: sample.at))
        }
    }

    // MARK: 通知からの操作

    /// 「停止」：今すぐ終了する。
    func stopNow() async {
        await endSession(at: .now)
        detector.reset()
    }

    /// 「誤検出なので破棄」：釣行を削除する（削除は分析に即時反映）。
    func discard(sessionID: UUID) {
        if activeSessionID == sessionID {
            scheduler.stop()
            location.startMonitoring()
            activeSessionID = nil
            detector.reset()
        }
        try? store.deleteSession(id: sessionID)
    }

    /// 現在の立ち位置に対応するポイント ID（撮影時の紐付けに使う）。
    func currentPointID() -> UUID? {
        guard let id = activeSessionID, let session = try? store.session(id: id),
              let coordinate = scheduler.currentCoordinate ?? session.track.last?.coordinate else { return nil }
        let key = Mesh.key(for: coordinate)
        return (try? store.points(spotID: session.spotID))?.first { $0.meshKey == key }?.id
    }
}
