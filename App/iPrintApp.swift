import SwiftUI
import SwiftData

@main
struct iPrintApp: App {
    var body: some Scene {
        WindowGroup {
            VaultView()
        }
        .modelContainer(for: StoredPurchase.self)
    }
}
