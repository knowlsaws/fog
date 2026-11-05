import Foundation

/// 低頻度 GPS の立ち位置サンプル（釣行詳細の軌跡）。
public struct TrackSample: Codable, Hashable, Sendable {
    public var at: Date
    public var coordinate: Coordinate

    public init(at: Date, coordinate: Coordinate) {
        self.at = at
        self.coordinate = coordinate
    }
}

/// 釣行中の活動量（CoreMotion / HealthKit。§2「活動」）。
public struct ActivitySummary: Codable, Hashable, Sendable {
    public var stepCount: Int?
    public var walkingDistanceM: Double?

    public init(stepCount: Int? = nil, walkingDistanceM: Double? = nil) {
        self.stepCount = stepCount
        self.walkingDistanceM = walkingDistanceM
    }
}

/// 釣行後レポート（F-21）。`summary` はログ画面の1行、`body` は全文。
public struct SessionReport: Codable, Hashable, Sendable {
    public var summary: String
    public var body: String
    public var generatedAt: Date

    public init(summary: String, body: String, generatedAt: Date) {
        self.summary = summary
        self.body = body
        self.generatedAt = generatedAt
    }
}

/// 釣行。自動で始まり自動で終わる（§3）。ボウズも記録する。
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var spotID: UUID
    public var startedAt: Date
    /// nil は記録中。
    public var endedAt: Date?
    public var snapshots: [EnvSnapshot]
    public var catches: [Catch]
    public var hookEvents: [HookEvent]
    public var track: [TrackSample]
    /// 釣行中に有効なタックル・リグ。前回から引き継ぎ、切替は例外的入力（F-14）。
    public var tackle: TackleKind?
    public var tackleID: UUID?
    public var rigID: UUID?
    /// false は手動（撮影から始まった等）。
    public var isAutoDetected: Bool
    public var activity: ActivitySummary?
    public var report: SessionReport?
    /// 釣行中の端末気圧計の記録（5 分ごと。F-35）。古いデータは nil
    public var pressureLog: [PressureSample]?

    public init(
        id: UUID = UUID(),
        spotID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        snapshots: [EnvSnapshot] = [],
        catches: [Catch] = [],
        tackle: TackleKind? = nil,
        rigID: UUID? = nil,
        hookEvents: [HookEvent] = [],
        track: [TrackSample] = [],
        tackleID: UUID? = nil,
        isAutoDetected: Bool = true,
        activity: ActivitySummary? = nil,
        report: SessionReport? = nil,
        pressureLog: [PressureSample]? = nil
    ) {
        self.id = id
        self.spotID = spotID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.snapshots = snapshots
        self.catches = catches
        self.hookEvents = hookEvents
        self.track = track
        self.tackle = tackle
        self.tackleID = tackleID
        self.rigID = rigID
        self.isAutoDetected = isAutoDetected
        self.activity = activity
        self.report = report
        self.pressureLog = pressureLog
    }

    /// ボウズ。
    public var isBlank: Bool { catches.isEmpty }
    /// 記録中は nil。
    public var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    public var isActive: Bool { endedAt == nil }
}
