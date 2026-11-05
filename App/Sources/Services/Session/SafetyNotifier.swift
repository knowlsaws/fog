import Foundation
import Core

/// 釣行中の安全通知（F-36）。釣行の開始時とホームの再計算時に予約し直し、釣行の終了で消す。
@MainActor
enum SafetyNotifier {
    static func schedule(at now: Date = .now, coordinate: Coordinate, environment: EnvironmentService,
                         timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        guard NotificationSettings.isEnabled(.safety) else { SessionNotifications.cancelSafety(); return }
        let sun = SunCalculator.times(on: now, at: coordinate, timeZone: timeZone)
        let tide = environment.tideStation(near: coordinate).map { TideEngine(station: $0) }
        let nextHigh = tide?.nextExtremes(after: now, count: 2).first { $0.kind == .high }?.at
        let alerts = SafetyPlanner.plan(now: now, sunset: sun.sunset, nextHighTide: nextHigh, homeTimeMinutes: NotificationSettings.homeTimeMinutes, timeZone: timeZone)
        SessionNotifications.safety(alerts, now: now)
    }

    static func cancel() { SessionNotifications.cancelSafety() }
}
