import Foundation
import WidgetKit
import Core

/// ホームの計算結果をウィジェット用スナップショットに書き出し、ウィジェットを更新する（§8）。
@MainActor
enum WidgetSync {
    static func publish(spotName: String, timeline: [ScorePoint], tide: TideEngine?, events: [ScoreEvent], isRecording: Bool, tackle: TackleKind?) {
        let points = timeline.map { p -> WidgetSnapshot.Point in
            var rising: Bool?
            if let tide {
                let rate = tide.rate(at: p.at)
                rising = abs(rate) < 2 ? nil : rate > 0
            }
            return WidgetSnapshot.Point(at: p.at, score: p.score, tideRising: rising, tideLevelCm: tide?.level(at: p.at))
        }
        let snapshot = WidgetSnapshot(spotName: spotName, points: points,
                                      events: events.map { WidgetSnapshot.Event(at: $0.at, label: $0.label) },
                                      isRecording: isRecording, tackle: tackle)
        FogShared.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 釣行の開始・終了で背景のオレンジを切り替える。
    static func setRecording(_ recording: Bool) {
        FogShared.updateSnapshot { $0.isRecording = recording }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func setTackle(_ tackle: TackleKind?) {
        FogShared.updateSnapshot { $0.tackle = tackle }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
