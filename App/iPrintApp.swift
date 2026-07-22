import SwiftUI
import SwiftData

@main
struct iPrintApp: App {
    var body: some Scene {
        WindowGroup {
            VaultView()
                .task { _ = await NotificationScheduler.shared.requestAuthorization() }
        }
        .modelContainer(for: StoredPurchase.self)
    }
}
