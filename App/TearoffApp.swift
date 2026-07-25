import SwiftUI
import SwiftData

@main
struct TearoffApp: App {
    @State private var store = StoreManager()
    /// User's appearance choice; drives the whole window's color scheme.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            VaultView()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                .task { _ = await NotificationScheduler.shared.requestAuthorization() }
                .task { await store.loadProducts() }
                .task {
                    #if DEBUG
                    MockData.seedIfNeeded(SharedModelContainer.shared.mainContext)
                    #endif
                }
                .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView()
                        .preferredColorScheme(appearance.colorScheme)
                }
        }
        // Shared so App Intents (Siri / Shortcuts) read and write the same store.
        .modelContainer(SharedModelContainer.shared)
    }
}
