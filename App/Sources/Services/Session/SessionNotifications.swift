import Foundation
import UserNotifications

/// 釣行の開始・終了の通知（§8）。開始通知から「停止」、誤検出なら「破棄」できる。レポート本文は L8/L14 で付ける。
enum SessionNotifications {
    static let startCategory = "fog.session.start"
    static let endCategory = "fog.session.end"
    static let stopAction = "fog.session.stop"
    static let discardAction = "fog.session.discard"

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
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = ["sessionID": sessionID.uuidString]
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
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
}
