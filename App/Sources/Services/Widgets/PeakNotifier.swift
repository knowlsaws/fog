import Foundation
import Core

/// 釣れ率ピーク通知（§8）：登録釣り場で今日のピークが 80 以上なら、その 1 時間前に 1 回だけ。
/// ホームの推移を計算するたびに呼ぶ。予報が変わって通知時刻が動いたときは、まだ鳴っていなければ差し替える。
@MainActor
enum PeakNotifier {
    private static let scheduledKey = "fog.peakNotified"

    static func schedule(points: [ScorePoint], spot: Spot?, now: Date = .now, timeZone: TimeZone) {
        guard let spot, spot.isRegistered, NotificationSettings.isEnabled(.peak) else { return }
        guard let plan = PeakNotificationPlanner.plan(points: points, now: now, timeZone: timeZone) else { return }
        let dayKey = PeakNotificationPlanner.dayKey(for: plan.peakStart, timeZone: timeZone)
        let defaults = UserDefaults.standard
        // 今日の分をすでに予約していて、その時刻を過ぎている（＝鳴った）なら 2 回目は出さない
        if let stored = defaults.dictionary(forKey: scheduledKey), stored["day"] as? String == dayKey,
           let fired = stored["fireAt"] as? Double, fired <= now.timeIntervalSince1970 {
            return
        }
        defaults.set(["day": dayKey, "fireAt": plan.fireAt.timeIntervalSince1970], forKey: scheduledKey)
        SessionNotifications.peak(spotName: spot.name, score: plan.maxScore, peakStart: plan.peakStart, fireAt: plan.fireAt, now: now, dayKey: dayKey, timeZone: timeZone)
    }
}
