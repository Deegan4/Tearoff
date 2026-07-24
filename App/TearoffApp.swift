import SwiftUI
import SwiftData

@main
struct TearoffApp: App {
    @State private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            VaultView()
                .environment(store)
                .task { _ = await NotificationScheduler.shared.requestAuthorization() }
                .task { await store.loadProducts() }
        }
        // Shared so App Intents (Siri / Shortcuts) read and write the same store.
        .modelContainer(SharedModelContainer.shared)
    }
}
