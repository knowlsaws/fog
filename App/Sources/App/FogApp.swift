import SwiftUI
import SwiftData
import UserNotifications

@main
struct FogApp: App {
    private let services: AppServices
    private let responder = NotificationResponder()

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
        }
        .modelContainer(services.persistence.container)
    }
}
