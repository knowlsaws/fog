import SwiftUI
import SwiftData

@main
struct FogApp: App {
    private let persistence: PersistenceController
    private let store: FogStore

    init() {
        let persistence = PersistenceController.live()
        self.persistence = persistence
        self.store = FogStore(container: persistence.container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .environment(store)
                .task { await MainActor.run { SampleSeeder.seedIfNeeded(store: store) } }
        }
        .modelContainer(persistence.container)
    }
}
