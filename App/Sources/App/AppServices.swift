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
        detection.onSessionEnded = { [photoImport] id in
            Task { @MainActor in await photoImport.importPhotos(for: id) }
        }
    }

    /// 起動時：ダミーデータ、通知、自動検出。
    func start() async {
        SampleSeeder.seedIfNeeded(store: store)
        await SessionNotifications.requestAuthorization()
        detection.start()
        _ = await PhotoLibraryService.requestAuthorization()
    }

    /// フォアグラウンド復帰：釣行中なら標準カメラの写真を取り込む（F-08）。
    func didBecomeActive() async {
        if let active = try? store.activeSession() {
            await photoImport.importPhotos(for: active.id)
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
