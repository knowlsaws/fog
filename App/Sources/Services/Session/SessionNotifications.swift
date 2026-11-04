import Foundation
import UserNotifications
import Core

/// 釣行の開始・終了の通知（§8）。開始通知から「停止」、誤検出なら「破棄」できる。レポート本文は L8/L14 で付ける。
enum SessionNotifications {
    static let startCategory = "fog.session.start"
    static let endCategory = "fog.session.end"
    static let stopAction = "fog.session.stop"
    static let discardAction = "fog.session.discard"
    static let recordCategory = "fog.record"
    static let peakCategory = "fog.peak"

    static func registerCategories() {
        let stop = UNNotificationAction(identifier: stopAction, title: "停止", options: [.destructive])
        let discard = UNNotificationAction(identifier: discardAction, title: "誤検出なので破棄", options: [.destructive])
        let start = UNNotificationCategory(identifier: startCategory, actions: [stop], intentIdentifiers: [], options: [])
        let end = UNNotificationCategory(identifier: endCategory, actions: [discard], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([start, end])
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func post(id: String, category: String, title: String, body: String, sessionID: UUID) {
        post(id: id, category: category, title: title, body: body, userInfo: ["sessionID": sessionID.uuidString], trigger: nil, timeSensitive: true)
    }

    static func post(id: String, category: String, title: String, body: String, userInfo: [String: String] = [:],
                     trigger: UNNotificationTrigger?, timeSensitive: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = userInfo
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func sessionStarted(spotName: String, sessionID: UUID) {
        guard NotificationSettings.isEnabled(.sessionStart) else { return }
        post(id: "session.start.\(sessionID)", category: startCategory, title: spotName, body: "記録を始めました", sessionID: sessionID)
    }

    static func sessionEnded(spotName: String, catches: Int, summary: String?, sessionID: UUID) {
        guard NotificationSettings.isEnabled(.sessionEnd) else { return }
        let body = summary ?? (catches == 0 ? "ボウズ" : "\(catches)尾")
        post(id: "session.end.\(sessionID)", category: endCategory, title: spotName, body: body, sessionID: sessionID)
    }

    /// 記録更新（初魚種・自己記録・釣り場記録）。アプリを閉じているときだけ呼ぶ（§8）。
    static func record(species: String, lengthCm: Double?, judgement: Analytics.RecordJudgement) {
        guard NotificationSettings.isEnabled(.record), judgement.hasAny else { return }
        let name = species.isEmpty ? "魚" : species
        let length = lengthCm.map { " \(Int($0.rounded())) cm" } ?? ""
        let title: String
        if judgement.isFirstSpecies { title = "初めての \(name)" }
        else if judgement.isPersonalBest { title = "自己記録 \(name)\(length)" }
        else { title = "この釣り場の記録 \(name)\(length)" }
        var parts: [String] = []
        if judgement.isPersonalBest, let prev = judgement.previousBestCm { parts.append("これまで \(Int(prev.rounded())) cm") }
        if judgement.isSpotRecord, !judgement.isPersonalBest { parts.append("釣り場記録") }
        post(id: "record.\(UUID().uuidString)", category: recordCategory, title: title, body: parts.joined(separator: " "), trigger: nil, timeSensitive: false)
    }

    /// 釣れ率ピーク：ピークの 1 時間前に 1 回。同じ日の予約は差し替える（ID が同じ）。
    static func peak(spotName: String, score: Int, peakStart: Date, fireAt: Date, now: Date, dayKey: String, timeZone: TimeZone) {
        guard NotificationSettings.isEnabled(.peak) else { return }
        let f = DateFormatter(); f.timeZone = timeZone; f.dateFormat = "H:mm"
        let interval = max(1, fireAt.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        post(id: "peak.\(dayKey)", category: peakCategory, title: spotName,
             body: "\(f.string(from: peakStart)) から釣れ率 \(score)", trigger: trigger, timeSensitive: false)
    }
}
