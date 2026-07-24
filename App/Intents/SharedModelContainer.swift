import SwiftData

/// One process-wide SwiftData container so the app scene and App Intents read
/// and write the same store. Backed by CloudKit so the vault syncs across the
/// user's devices — a receipt vault is insurance you can't afford to lose with
/// the phone. Falls back to a purely local store if CloudKit is unavailable
/// (not signed into iCloud, or a dev build without the container provisioned),
/// so the app always works.
enum SharedModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([StoredPurchase.self])
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return container
        }
        let local = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not create the shared ModelContainer: \(error)")
        }
    }()
}
