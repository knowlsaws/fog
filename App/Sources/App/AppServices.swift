import Foundation
import SwiftData
import UserNotifications
import Core

/// アプリ全体で共有するサービス群。`FogApp` が生成し、環境に流す。
@MainActor
@Observable
final class AppServices {
    let persistence: PersistenceController
    let store: FogStore
    let environment: EnvironmentService
    let location: LocationService
    let scheduler: SnapshotScheduler
    let detection: SessionDetectionService
    let capture: CaptureService
    let photoImport: PhotoImportService
    let report: ReportService
    let feeds = FeedService()
    let inventory = InventoryStore()
    let router = Router()
    var dataManager: DataManager { DataManager(store: store) }

    init() {
        let persistence = PersistenceController.live()
        let store = FogStore(container: persistence.container)
        let environment = EnvironmentService.live()
        let location = LocationService()
        let scheduler = SnapshotScheduler(environment: environment, store: store)
        self.persistence = persistence
        self.store = store
        self.environment = environment
        self.location = location
        self.scheduler = scheduler
        let detection = SessionDetectionService(location: location, store: store, scheduler: scheduler, environment: environment)
        self.detection = detection
        let capture = CaptureService(store: store, environment: environment, detection: detection)
        self.capture = capture
        self.photoImport = PhotoImportService(store: store, capture: capture)
        let report = ReportService(store: store)
        self.report = report
        detection.onSessionEnded = { [photoImport] id in
            Task { @MainActor in
                await photoImport.importPhotos(for: id)
                if let s = await report.attachReport(to: id) {
                    SessionNotifications.sessionEnded(spotName: (try? store.spot(id: s.spotID))?.name ?? "釣り場", catches: s.catches.count, summary: s.report?.summary, sessionID: id)
                }
            }
        }
    }

    var hookRecorder: HookEventRecorder { HookEventRecorder(store: store, detection: detection, scheduler: scheduler, capture: capture, inventory: inventory) }

    /// 起動時：ダミーデータ、通知、自動検出。
    func start() async {
        RouterHolder.shared.router = router
        CatalogSeeder.seedIfNeeded(store: store)
        await SessionNotifications.requestAuthorization()
        detection.start()
        drainPendingHookEvents()
        _ = await PhotoLibraryService.requestAuthorization()
    }

    /// フォアグラウンド復帰：ウィジェットからの針ロストを取り込み、釣行中なら標準カメラの写真を取り込む（F-08）。
    func didBecomeActive() async {
        drainPendingHookEvents()
        if let active = try? store.activeSession() {
            await photoImport.importPhotos(for: active.id)
        }
    }

    /// ウィジェットの「針ロスト」はアプリを開かずに時刻だけ記録される。ここで釣行・位置を補って保存する（F-15）。
    func drainPendingHookEvents() {
        for date in FogShared.takePendingHookLost() {
            hookRecorder.record(.lost, at: date)
        }
    }
}

/// 通知のアクション（停止・破棄）を受ける。
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    weak var services: AppServices?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let services, let idString = response.notification.request.content.userInfo["sessionID"] as? String,
              let sessionID = UUID(uuidString: idString) else { return }
        switch response.actionIdentifier {
        case SessionNotifications.stopAction:
            await services.detection.stopNow()
        case SessionNotifications.discardAction:
            await MainActor.run { services.detection.discard(sessionID: sessionID) }
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
