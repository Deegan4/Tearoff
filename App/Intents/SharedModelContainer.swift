import SwiftData

/// One process-wide SwiftData container so the app scene and App Intents read
/// and write the same store. Without this, an intent would open a second,
/// empty container and never see the user's purchases.
enum SharedModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: StoredPurchase.self)
        } catch {
            fatalError("Could not create the shared ModelContainer: \(error)")
        }
    }()
}
