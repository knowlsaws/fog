import Foundation
import SwiftData
import Core

/// `Core.Session` の SwiftData 表現。釣果・スナップショット・針イベントは子レコード、軌跡とレポートは JSON で埋め込む。
@Model
final class SessionRecord {
    var uuid: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var tackleKindRaw: String? = nil
    var tackleID: UUID? = nil
    var rigID: UUID? = nil
    var isAutoDetected: Bool = true

    var stepCount: Int? = nil
    var walkingDistanceM: Double? = nil

    var reportSummary: String? = nil
    var reportBody: String? = nil
    var reportGeneratedAt: Date? = nil

    /// `[TrackSample]` の JSON。
    var trackData: Data? = nil

    var spot: SpotRecord? = nil

    @Relationship(deleteRule: .cascade, inverse: \CatchRecord.session)
    var catches: [CatchRecord]? = nil

    @Relationship(deleteRule: .cascade, inverse: \EnvSnapshotRecord.session)
    var snapshots: [EnvSnapshotRecord]? = nil

    @Relationship(deleteRule: .cascade, inverse: \HookEventRecord.session)
    var hookEvents: [HookEventRecord]? = nil

    init(core: Core.Session, spot: SpotRecord) {
        uuid = core.id
        self.spot = spot
        applyScalars(core)
    }

    /// 子レコード以外を反映する。子は `FogStore` が同期する。
    func applyScalars(_ core: Core.Session) {
        startedAt = core.startedAt
        endedAt = core.endedAt
        tackleKindRaw = core.tackle?.rawValue
        tackleID = core.tackleID
        rigID = core.rigID
        isAutoDetected = core.isAutoDetected
        stepCount = core.activity?.stepCount
        walkingDistanceM = core.activity?.walkingDistanceM
        reportSummary = core.report?.summary
        reportBody = core.report?.body
        reportGeneratedAt = core.report?.generatedAt
        trackData = core.track.isEmpty ? nil : BlobCodec.encode(core.track)
    }

    /// 釣り場が消えていれば nil（cascade で同時に消えるので通常は起きない）。
    var core: Core.Session? {
        guard let spotID = spot?.uuid else { return nil }
        let activity: ActivitySummary? = (stepCount == nil && walkingDistanceM == nil) ? nil : ActivitySummary(stepCount: stepCount, walkingDistanceM: walkingDistanceM)
        var report: SessionReport?
        if let reportSummary, let reportBody, let reportGeneratedAt {
            report = SessionReport(summary: reportSummary, body: reportBody, generatedAt: reportGeneratedAt)
        }
        return Core.Session(
            id: uuid,
            spotID: spotID,
            startedAt: startedAt,
            endedAt: endedAt,
            snapshots: (snapshots ?? []).map(\.core).sorted { $0.at < $1.at },
            catches: (catches ?? []).map { $0.core(sessionID: uuid) }.sorted { $0.at < $1.at },
            tackle: tackleKindRaw.flatMap(TackleKind.init(rawValue:)),
            rigID: rigID,
            hookEvents: (hookEvents ?? []).map { $0.core(sessionID: uuid) }.sorted { $0.at < $1.at },
            track: BlobCodec.decode([TrackSample].self, from: trackData) ?? [],
            tackleID: tackleID,
            isAutoDetected: isAutoDetected,
            activity: activity,
            report: report
        )
    }
}
