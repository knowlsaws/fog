import Foundation
import Core

/// 明日のベストタイム通知（F-28）：ホームの推移を計算するたびに、明日 1 日分から最良の時間帯を選んで今日の 20 時に予約する。
/// 条件（登録釣り場だけ・週末だけ）は `NotificationSettings`。同じ日の予約は差し替える。
@MainActor
enum DailyBriefNotifier {
    static func schedule(points: [ScorePoint], extremes: [TideExtreme], spot: Spot?, coordinate: Coordinate,
                         airTemperatureAt: (Date) -> Double?, now: Date = .now, timeZone: TimeZone) {
        guard NotificationSettings.isEnabled(.dailyBrief) else { return }
        if NotificationSettings.briefRegisteredOnly, !(spot?.isRegistered ?? false) { return }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let tomorrow = cal.startOfDay(for: now).addingTimeInterval(86_400)
        if NotificationSettings.briefWeekendOnly {
            let c = cal.dateComponents([.year, .month, .day, .weekday], from: tomorrow)
            let weekend = c.weekday == 1 || c.weekday == 7 || JapaneseHolidays.isHoliday(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
            guard weekend else { return }
        }
        let sun = SunCalculator.times(on: tomorrow.addingTimeInterval(12 * 3600), at: coordinate, timeZone: timeZone)
        guard let window = ScoreTimeline.bestWindow(points) else { return }
        let brief = DailyBriefPlanner.plan(points: points, extremes: extremes, sun: sun, airTemperatureC: airTemperatureAt(window.start),
                                           now: now, spotName: spot?.name ?? "現在地", timeZone: timeZone)
        guard let brief else { return }
        SessionNotifications.dailyBrief(brief, now: now, dayKey: PeakNotificationPlanner.dayKey(for: tomorrow, timeZone: timeZone))
    }
}
