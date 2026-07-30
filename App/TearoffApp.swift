import SwiftUI
import SwiftData

@main
struct TearoffApp: App {
    @State private var store = StoreManager()
    @Environment(\.scenePhase) private var scenePhase
    /// User's appearance choice; drives the whole window's color scheme.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            VaultView()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                // Ask for notifications only once onboarding has explained why
                // they matter — a cold prompt on first launch (over the top of
                // onboarding, no less) reads as spam and gets denied.
                .task(id: hasCompletedOnboarding) {
                    guard hasCompletedOnboarding else { return }
                    _ = await NotificationScheduler.shared.requestAuthorization()
                }
                .task { await store.loadProducts() }
                // A promo code or IAP redeemed in the App Store unlocks Pro
                // while Tearoff is suspended in the background. Nothing
                // recomputes on resume otherwise, so the user comes back to a
                // still-locked app and reasonably assumes the code failed.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await store.refreshEntitlements() }
                }
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
