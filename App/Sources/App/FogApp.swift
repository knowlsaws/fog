import SwiftUI
import SwiftData
import UserNotifications


@main
struct FogApp: App {
    private let services: AppServices
    private let responder = NotificationResponder()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let services = AppServices()
        self.services = services
        responder.services = services
        UNUserNotificationCenter.current().delegate = responder
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .environment(services)
                .environment(services.store)
                .task { await services.start() }
                .onOpenURL { url in
                    if let link = DeepLink.parse(url) { services.router.pending = link }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await services.didBecomeActive() } }
                }
        }
        .modelContainer(services.persistence.container)
    }
}
