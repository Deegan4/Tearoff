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
        .modelContainer(for: StoredPurchase.self)
    }
}
